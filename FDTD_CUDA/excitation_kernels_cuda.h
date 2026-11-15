#ifndef EXCITATION_KERNELS_CUDA_H
#define EXCITATION_KERNELS_CUDA_H

#include <cuda_runtime.h>

//! Soft excitation, deterministic: one thread per distinct field value.
/*!
  field: the engine's float4 array viewed as float; off[g] = 4*cellIndex + component of group g.
  The entries [first[g], first[g+1]) of amp/delay all address that field value. They are added one after
  the other in their original order, exactly like Engine_Ext_Excitation does it on the host, so that the
  result does not depend on the thread scheduling (no atomicAdd).
  The signal position of an entry is computed exactly like in Engine_Ext_Excitation:
    pos = numTS - delay; pos = 0 if pos <= 0; pos %= period; pos = 0 if pos >= length
*/
cudaError_t Exc_Launch(float* field, const unsigned long long* off, const unsigned int* first,
                       const float* amp, const unsigned int* delay, unsigned int groups,
                       const float* signal, int numTS, int period, int length);

#endif // EXCITATION_KERNELS_CUDA_H
