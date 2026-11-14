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
#include <cstring>
#include <stdexcept>
#include <string>

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

//! environment switch: set and not "0"
static bool EnvFlag(const char* name)
{
	const char* v = getenv(name);
	return v != NULL && v[0] != '\0' && strcmp(v, "0") != 0;
}

void Engine_CUDA::InitExtensions()
{
	// OPENEMS_CUDA_HOST_EXT=1: use the host versions of all extensions (reference for comparisons)
	const bool hostOnly = EnvFlag("OPENEMS_CUDA_HOST_EXT");
	// OPENEMS_CUDA_ALLOW_HOST_EXT=1: extensions without a GPU version may run on the host (slow).
	// Without it such a model is refused instead of being computed partly on the host.
	const bool allowHost = hostOnly || EnvFlag("OPENEMS_CUDA_ALLOW_HOST_EXT");

	std::string unsupported;
	for (size_t n = 0; n < Op->GetNumberOfExtentions(); ++n)
	{
		Operator_Extension* op_ext = Op->GetExtension(n);
		Engine_Extension* eng_ext = hostOnly ? NULL : CreateCudaEngineExtension(op_ext, this);
		if (!eng_ext)
		{
			eng_ext = op_ext->CreateEngineExtention();
			if (eng_ext && !allowHost)
				unsupported += std::string(unsupported.empty() ? "" : ", ") + op_ext->GetExtensionName();
		}
		if (eng_ext)
		{
			eng_ext->SetEngine(this);
			m_Eng_exts.push_back(eng_ext); // also when refused: the engine cleans them up
		}
	}

	if (!unsupported.empty())
		throw std::runtime_error(
			"CUDA engine: the model uses extensions that have no GPU implementation yet: " + unsupported + ".\n"
			"  Choose another engine (--engine=multithreaded), or allow these extensions to run on the host\n"
			"  (slow, the fields are copied between GPU and host) with OPENEMS_CUDA_ALLOW_HOST_EXT=1.");
}
