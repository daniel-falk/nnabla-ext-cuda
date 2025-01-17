// Copyright 2017,2018,2019,2020,2021 Sony Corporation.
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

#ifndef __NBLA_CUDA_UTILS_RANDOM_HPP__
#define __NBLA_CUDA_UTILS_RANDOM_HPP__

#include <curand_kernel.h>
#include <nbla/array.hpp>
#include <nbla/cuda/common.hpp>
#include <nbla/variable.hpp>

namespace nbla {

/** Returns a new cuRand generator initialized with a given seed.

@param[in] seed Seed of rng. When -1 given, the generator is not initialized
without seed.

@retval cuRand generator.
 */
curandGenerator_t curand_create_generator(int seed = -1);

/** Destroy a cuRand generator object.

@param[in,out] gen cuRand generator.
 */
void curand_destroy_generator(curandGenerator_t gen);

/** Set random seed to cuRand generator object.

@param[in,out] gen cuRand generator.
@param[in] seed Seed.
 */
void curand_set_seed(curandGenerator_t gen, int seed);

/** Generate random values from uniform distribution in [low, high).

@param[in,out] gen cuRand generator.
@param[in] low Minimum value of uniform dist.
@param[in] high Upperbound of uniform dist.
@param[out] dev_ptr Device array pointer.
@param[in] size Array size.

@note T=int generates random integers in the range of [low, high).
 */
template <typename T>
void curand_generate_rand(curandGenerator_t gen, T low, T high, T *dev_ptr,
                          size_t size);

/** Generate random values from normal distribution with mean and stddev.

@param[in,out] gen cuRand generator.
@param[in] mu Mean of normal dist.
@param[in] sigma Standard deviation of normal dist.
@param[out] dev_ptr Device array pointer.
@param[in] size Array size.
 */
template <typename T>
void curand_generate_randn(curandGenerator_t gen, T mu, T sigma, T *dev_ptr,
                           size_t size);

void curand_initialize(const int size, const int seed, const int offset,
                       curandState *state);

// Support functions for recomputation
template <typename T>
void save_output_data(const Context &ctx, Variable *output, NdArray &buffer) {
  const Array *y = output->data()->get(get_dtype<T>(), ctx);
  Array *buffer_array = buffer.cast(get_dtype<T>(), ctx, true);
  buffer_array->copy_from(y);
}

template <typename T>
void restore_output_data(const Context &ctx, NdArray &buffer,
                         Variable *output) {
  const Array *buffer_array = buffer.get(get_dtype<T>(), ctx);
  Array *y = output->data()->cast(get_dtype<T>(), ctx, true);
  y->copy_from(buffer_array);
  buffer.array()->clear();
}
}

#endif
