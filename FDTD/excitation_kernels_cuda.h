#ifndef EXCITATION_KERNELS_CUDA_H
#define EXCITATION_KERNELS_CUDA_H

#include <cuda_runtime.h>

//! Soft excitation: field[off[n]] += amp[n] * signal[pos(n)] for n < count
/*!
  field: the engine's float4 array viewed as float, off[n] = 4*cellIndex + component.
  pos(n) is computed exactly like in Engine_Ext_Excitation:
    pos = numTS - delay[n]; pos = 0 if pos <= 0; pos %= period; pos = 0 if pos >= length
  atomicAdd is used because several entries may address the same field value.
*/
cudaError_t Exc_Launch(float* field, const unsigned long long* off, const float* amp, const unsigned int* delay,
                       unsigned int count, const float* signal, int numTS, int period, int length);

#endif // EXCITATION_KERNELS_CUDA_H
