// Copyright 2017,2018,2019,2020,2021 Sony Corporation.
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

/** Identity
 */
#ifndef __NBLA_CUDA_FUNCTION_IDENTITY_HPP__
#define __NBLA_CUDA_FUNCTION_IDENTITY_HPP__

#include <nbla/cuda/cuda.hpp>
#include <nbla/function/identity.hpp>
namespace nbla {
/** @copydoc Identity
*/

template <typename T> class IdentityCuda : public Identity<T> {

public:
  typedef typename CudaType<T>::type Tc;
  explicit IdentityCuda(const Context &ctx)
      : Identity<T>(ctx), device_(std::stoi(ctx.device_id)) {}
  virtual ~IdentityCuda() {}
  virtual string name() { return "IdentityCuda"; }
  virtual vector<string> allowed_array_classes() {
    return SingletonManager::get<Cuda>()->array_classes();
  }

protected:
  int device_;
  virtual void forward_impl(const Variables &inputs, const Variables &outputs);
  virtual void backward_impl(const Variables &inputs, const Variables &outputs,
                             const vector<bool> &propagate_down,
                             const vector<bool> &accum);
};
}

#endif
