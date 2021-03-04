// Copyright (c) 2017 Sony Corporation. All Rights Reserved.
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

#include <nbla/array.hpp>
#include <nbla/cuda/common.hpp>
#include <nbla/cuda/function/epsilon_insensitive_loss.hpp>
#include <nbla/cuda/function/utils/base_transform_binary.cuh>
#include <nbla/cuda/math.hpp>
#include <nbla/variable.hpp>

namespace nbla {

NBLA_DEFINE_TRANSFORM_BINARY_CUDA_1(
    EpsilonInsensitiveLoss,
    (fabs(x0 - x1) > (T)a0) ? (fabs((x0 - x1)) - (T)a0) : (T)0,
    (x0 - x1) > (T)a0 ? dy : ((x0 - x1) < (T)-a0) ? -dy : (T)0,
    (x0 - x1) > (T)a0 ? -dy : ((x0 - x1) < (T)-a0) ? dy : (T)0, false, false,
    true, true, float);
}
