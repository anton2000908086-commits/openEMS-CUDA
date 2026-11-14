#ifndef ENGINE_INTERFACE_CUDA_H
#define ENGINE_INTERFACE_CUDA_H

#include "engine_interface_fdtd.h"

//! Engine interface for the CUDA engine.
/*!
  Field reads of the probes go through Engine_CUDA::GetVolt/GetCurr (single values are read straight
  from the GPU, see there). The energy estimate for the end criterion is summed on the GPU, so the
  fields no longer have to be copied to the host for it.
*/
class Engine_Interface_CUDA : public Engine_Interface_FDTD
{
public:
	Engine_Interface_CUDA(Operator* op);
	virtual ~Engine_Interface_CUDA();

	virtual double CalcFastEnergy() const;
};

#endif // ENGINE_INTERFACE_CUDA_H
