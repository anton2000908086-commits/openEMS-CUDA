#ifndef ENGINE_EXT_UPML_CUDA_H
#define ENGINE_EXT_UPML_CUDA_H

#include <string>
#include <vector>
#include "extensions/engine_extension.h"
#include "upml_kernels_cuda.h"

class Operator_Ext_UPML;
class Engine_CUDA;

//! UPML on the GPU: the fluxes and the coefficients of one PML box live in GPU memory,
//! the fields are the engine's own GPU arrays. No host<->GPU copies during the simulation
//! (only a copy of host-side field changes made by other, still host-based, extensions).
class Engine_Ext_UPML_CUDA : public Engine_Extension
{
public:
	Engine_Ext_UPML_CUDA(Operator_Ext_UPML* op_ext, Engine_CUDA* eng);
	virtual ~Engine_Ext_UPML_CUDA();

	virtual void DoPreVoltageUpdates();
	virtual void DoPostVoltageUpdates();
	virtual void DoPreCurrentUpdates();
	virtual void DoPostCurrentUpdates();

	virtual std::string GetExtensionName() const;

private:
	Engine_CUDA* m_EngCuda;
	UPMLBoxGeom m_Geom;
	size_t m_BoxCells;

	float4* d_vv;   float4* d_vvfo; float4* d_vvfn;
	float4* d_ii;   float4* d_iifo; float4* d_iifn;
	float4* d_volt_flux; float4* d_curr_flux;

	void Free();
};

#endif // ENGINE_EXT_UPML_CUDA_H
