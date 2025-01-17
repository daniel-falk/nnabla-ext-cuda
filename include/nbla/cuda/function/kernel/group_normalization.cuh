// Copyright 2021 Sony Group Corporation.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <nbla/cuda/common.hpp>
#include <nbla/cuda/utils/block_reduce.cuh>
#include <nbla/cuda/utils/warp_reduce.cuh>

namespace nbla {

// Use custom maximum blocks constant because NBLA_CUDA_MAX_BLOCKS is 65536
// which does not match official CUDA document.
constexpr size_t NBLA_CUDA_GN_MAX_BLOCKS = 65535;
constexpr size_t NBLA_CUDA_GN_NUM_THREADS = NBLA_CUDA_NUM_THREADS;
constexpr int NBLA_CUDA_GN_N_UNROLL = 4;

/**
 * Calculate `a` and `b` of simplified normalization formula `y = a * x + b`.
 * Original formula is `y = gamma * (x - mean) / sqrt(var) + beta`. Thus `a =
 * gamma / sqrt(var), b = beta - gamma * mean / sqrt(var).`
 */
template <typename T, typename IndexT>
__global__ void group_norm_forward_normalization_factor(
    const IndexT batch_size, const IndexT channel_size, const int num_groups,
    const T *mean, const T *var, const T *beta, const T *gamma, T *a, T *b,
    const float eps) {

  const auto outer_size = batch_size * channel_size;
  // Grid-stride loop
  for (IndexT idx = blockIdx.x * blockDim.x + threadIdx.x; idx < outer_size;
       idx += gridDim.x * blockDim.x) {
    const IndexT stats_idx = idx / (channel_size / num_groups);
    const IndexT param_idx = idx % channel_size;
    const T scale = gamma ? gamma[param_idx] : (T)1.0f;
    const T bias = beta ? beta[param_idx] : (T)0.0f;

    const T invstd = rsqrt(var[stats_idx] + eps);
    const T scale_invstd = scale * invstd;
    a[idx] = scale_invstd;
    b[idx] = bias - mean[stats_idx] * scale_invstd;
  }
}

template <typename T, typename IndexT, IndexT N_UNROLL>
__global__ void
group_norm_forward_normalization(const IndexT size, const IndexT spatial_size,
                                 const T *x, const T *a, const T *b, T *y) {
  const auto elements_per_block = blockDim.x * N_UNROLL;

  // Grid-stride loop
  for (IndexT offset = blockIdx.x * elements_per_block + threadIdx.x;
       offset < size; offset += gridDim.x * elements_per_block) {

#pragma unroll
    for (auto i = 0; i < N_UNROLL; i++) {
      const IndexT idx = offset + i * blockDim.x;
      if (idx < size) {
        const IndexT ab_idx = idx / spatial_size;
        y[idx] = a[ab_idx] * x[idx] + b[ab_idx];
      }
    }
  }
}

template <typename T, typename IndexT, IndexT N_UNROLL>
__global__ void group_norm_backward_gamma_invstd(
    const IndexT size, const IndexT channel_size, const int num_groups,
    const T *gamma, const T *var, T *gamma_invstd, const float eps) {
  const auto elements_per_block = blockDim.x * N_UNROLL;

  // Grid-stride loop
  for (IndexT offset = blockIdx.x * elements_per_block + threadIdx.x;
       offset < size; offset += gridDim.x * elements_per_block) {

#pragma unroll
    for (auto i = 0; i < N_UNROLL; i++) {
      const IndexT idx = offset + i * blockDim.x;
      if (idx < size) {
        const IndexT stats_idx = idx / (channel_size / num_groups);
        const IndexT param_idx = idx % channel_size;
        const T scale = gamma ? gamma[param_idx] : (T)1.0f;
        gamma_invstd[idx] = scale * rsqrt(var[stats_idx] + eps);
      }
    }
  }
}

template <typename T, typename IndexT>
__global__ void group_norm_backward_dx_factor(
    const IndexT batch_size, const IndexT channel_size,
    const IndexT spatial_size, const float inv_reduce_size,
    const int num_groups, const T *mean, const T *var, const T *dmean,
    const T *dvar, const T *gamma, const T *sum_dy, const T *sum_dyx,
    T *factor1, T *factor2, const float eps) {
  const IndexT tidx = threadIdx.x;
  const IndexT bdimx = blockDim.x;

  const IndexT chunk_size = channel_size / num_groups;

  // Grid-stride loop for batch
  for (IndexT bidx = blockIdx.x; bidx < batch_size; bidx += gridDim.x) {
    // Grid-stride loop for group
    for (IndexT bidy = blockIdx.y; bidy < num_groups; bidy += gridDim.y) {

      // Load and reduce
      float sum_dy_gamma = 0.0f;
      float sum_dyx_gamma = 0.0f;
      for (IndexT i = tidx; i < chunk_size; i += bdimx) {
        const IndexT idx = (bidx * num_groups + bidy) * chunk_size + i;
        const IndexT param_idx = bidy * chunk_size + i;
        const T scale = gamma ? gamma[param_idx] : (T)1.0f;
        sum_dy_gamma += static_cast<float>(sum_dy[idx] * scale);
        sum_dyx_gamma += static_cast<float>(sum_dyx[idx] * scale);
      }

      if (bdimx <= CUDA_WARP_SIZE) {
        sum_dy_gamma = warpReduceSum(sum_dy_gamma);
        sum_dyx_gamma = warpReduceSum(sum_dyx_gamma);
      } else {
        sum_dy_gamma = blockReduceSum(sum_dy_gamma);
        sum_dyx_gamma = blockReduceSum(sum_dyx_gamma);
      }

      // Store
      if (threadIdx.x == 0) {
        const IndexT stats_idx = bidx * num_groups + bidy;
        const float invstd = rsqrt(var[stats_idx] + eps);
        const float tmp =
            (sum_dy_gamma * mean[stats_idx] - sum_dyx_gamma) * invstd * invstd *
                invstd * inv_reduce_size +
            (dvar ? 2.0f * dvar[stats_idx] * inv_reduce_size : 0.0f);
        factor1[stats_idx] = tmp;
        factor2[stats_idx] =
            -tmp * mean[stats_idx] - sum_dy_gamma * invstd * inv_reduce_size +
            (dmean ? dmean[stats_idx] * inv_reduce_size : 0.0f);
      }
    }
  }
}

template <bool accum, typename T, typename IndexT, IndexT N_UNROLL>
__global__ void
group_norm_backward_dx(const IndexT size, const IndexT channel_size,
                       const IndexT spatial_size, const int num_groups,
                       const T *x, const T *dy, const T *gamma_invstd,
                       const T *factor1, const T *factor2, T *dx) {
  const auto elements_per_block = blockDim.x * N_UNROLL;

  // Grid-stride loop
  for (IndexT offset = blockIdx.x * elements_per_block + threadIdx.x;
       offset < size; offset += gridDim.x * elements_per_block) {

#pragma unroll
    for (auto i = 0; i < N_UNROLL; i++) {
      const IndexT idx = offset + i * blockDim.x;
      if (idx < size) {
        const IndexT factor_idx =
            idx / (spatial_size * (channel_size / num_groups));
        const IndexT param_idx = idx / (spatial_size);
        dx[idx] = gamma_invstd[param_idx] * dy[idx] +
                  factor1[factor_idx] * x[idx] + factor2[factor_idx] +
                  (accum ? dx[idx] : (T)0.0f);
      }
    }
  }
}

template <bool beta_accum, bool gamma_accum, typename T, typename IndexT>
__global__ void group_norm_backward_dbeta_dgamma(
    const IndexT batch_size, const IndexT channel_size, const int num_groups,
    const T *mean, const T *var, const T *sum_dy, const T *sum_dyx, T *dbeta,
    T *dgamma, const float eps) {
  // Grid-stride loop
  for (IndexT idx = blockIdx.x * blockDim.x + threadIdx.x; idx < channel_size;
       idx += gridDim.x * blockDim.x) {
    const IndexT chunk_size = channel_size / num_groups;

    float db = 0.0f;
    float dg = 0.0f;

    for (IndexT n = 0; n < batch_size; n++) {
      const IndexT param_idx = n * channel_size + idx;
      const IndexT stats_idx = n * num_groups + idx / chunk_size;
      db += static_cast<float>(sum_dy[param_idx]);
      dg += (sum_dyx[param_idx] - sum_dy[param_idx] * mean[stats_idx]) *
            rsqrt(var[stats_idx] + eps);
    }

    if (dbeta) {
      dbeta[idx] = db + (beta_accum ? dbeta[idx] : (T)0.0f);
    }
    if (dgamma) {
      dgamma[idx] = dg + (gamma_accum ? dgamma[idx] : (T)0.0f);
    }
  }
}
}
