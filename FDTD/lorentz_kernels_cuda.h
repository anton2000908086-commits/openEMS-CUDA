#ifndef LORENTZ_KERNELS_CUDA_H
#define LORENTZ_KERNELS_CUDA_H

#include <cuda_runtime.h>

//! ADE pre update for one dispersion order (same code for voltages and currents).
/*!
  For every listed cell k (flat index into the float4 field array), component c = x,y,z:
    with Lorentz term (lor != NULL):  lor += cLor*ade;  ade = ade*cInt + cExt*(F - lor)
    without:                          ade = ade*cInt + cExt*F
  The field is not changed.
*/
cudaError_t Lor_LaunchPre(const float4* field, const unsigned long long* cell, unsigned int count,
                          float4* ade, float4* lor, const float4* cLor, const float4* cInt, const float4* cExt);

//! ADE apply: F -= ade (the cells of one order are unique, so there is no write conflict)
cudaError_t Lor_LaunchApply(float4* field, const unsigned long long* cell, unsigned int count, const float4* ade);

#endif // LORENTZ_KERNELS_CUDA_H
