// Engine_CUDA: choice between GPU and host implementation of the engine extensions.
// Kept in a plain .cpp (not in engine_cuda.cu) so that the operator extension headers
// are compiled by the host compiler only.
#include "engine_cuda.h"
#include "engine_ext_upml_cuda.h"
#include "engine_ext_excitation_cuda.h"
#include "engine_ext_lorentz_cuda.h"
#include "extensions/operator_ext_lorentzmaterial.h"
#include "extensions/operator_ext_excitation.h"
#include "extensions/operator_extension.h"
#include "extensions/operator_ext_upml.h"
#include "extensions/engine_extension.h"

#include <cstdlib>

//! the GPU version of an extension, or NULL if there is none (the host version is used then)
static Engine_Extension* CreateCudaEngineExtension(Operator_Extension* op_ext, Engine_CUDA* eng)
{
	if (Operator_Ext_UPML* upml = dynamic_cast<Operator_Ext_UPML*>(op_ext))
		return new Engine_Ext_UPML_CUDA(upml, eng);
	if (Operator_Ext_Excitation* exc = dynamic_cast<Operator_Ext_Excitation*>(op_ext))
		return new Engine_Ext_Excitation_CUDA(exc, eng);
	// also catches the Conducting Sheet extension (derived from the Lorentz extension)
	if (Operator_Ext_LorentzMaterial* lor = dynamic_cast<Operator_Ext_LorentzMaterial*>(op_ext))
		return new Engine_Ext_Lorentz_CUDA(lor, eng);
	return NULL;
}

void Engine_CUDA::InitExtensions()
{
	// OPENEMS_CUDA_HOST_EXT=1: use the host versions of all extensions (reference for comparisons)
	const bool hostOnly = (getenv("OPENEMS_CUDA_HOST_EXT") != NULL);

	for (size_t n = 0; n < Op->GetNumberOfExtentions(); ++n)
	{
		Operator_Extension* op_ext = Op->GetExtension(n);
		Engine_Extension* eng_ext = hostOnly ? NULL : CreateCudaEngineExtension(op_ext, this);
		if (!eng_ext)
			eng_ext = op_ext->CreateEngineExtention();
		if (eng_ext)
		{
			eng_ext->SetEngine(this);
			m_Eng_exts.push_back(eng_ext);
		}
	}
}
