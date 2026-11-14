#ifndef UPML_KERNELS_CUDA_H
#define UPML_KERNELS_CUDA_H

#include <cuda_runtime.h>

//! geometry of one UPML box inside the FDTD grid (plain data, no openEMS headers: used by the .cu file)
struct UPMLBoxGeom
{
	unsigned int start[3]; //!< first cell of the box in the FDTD grid
	unsigned int n[3];     //!< number of cells of the box
	unsigned int N[3];     //!< number of lines of the whole FDTD grid
};

//! Pre update: f = c*F - cfo*flux;  F = flux;  flux = f      (F = voltage or current, same for both)
cudaError_t UPML_LaunchPre(float4* field, float4* flux, const float4* c, const float4* cfo, const UPMLBoxGeom& g);

//! Post update: f = flux;  flux = F;  F = f + cfn*flux
cudaError_t UPML_LaunchPost(float4* field, float4* flux, const float4* cfn, const UPMLBoxGeom& g);

#endif // UPML_KERNELS_CUDA_H
