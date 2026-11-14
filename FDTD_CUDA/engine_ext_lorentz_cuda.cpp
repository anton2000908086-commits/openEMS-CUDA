#include "engine_ext_lorentz_cuda.h"
#include "engine_cuda.h"
#include "extensions/operator_ext_lorentzmaterial.h"

#include <stdexcept>
#include <string>
#include <vector>

#define LOR_CUDA_CHECK(call) \
	do { \
		cudaError_t err_ = (call); \
		if (err_ != cudaSuccess) \
			throw std::runtime_error(std::string("CUDA Lorentz/ConductingSheet: ") + cudaGetErrorString(err_) \
				+ " (" + __FILE__ + ":" + std::to_string(__LINE__) + ")"); \
	} while (0)

//! pack arr[0..2][i] (i < count) into a float4 array on the GPU; arr == NULL gives zeros
static float4* UploadVec3(FDTD_FLOAT*** arr3, int o, unsigned int count, bool zero)
{
	std::vector<float4> h(count);
	for (unsigned int i = 0; i < count; ++i)
	{
		float4 v = {0.0f, 0.0f, 0.0f, 0.0f};
		if (!zero)
		{
			v.x = (float)arr3[o][0][i];
			v.y = (float)arr3[o][1][i];
			v.z = (float)arr3[o][2][i];
		}
		h[i] = v;
	}
	float4* d = NULL;
	LOR_CUDA_CHECK(cudaMalloc((void**)&d, count * sizeof(float4)));
	LOR_CUDA_CHECK(cudaMemcpy(d, h.data(), count * sizeof(float4), cudaMemcpyHostToDevice));
	return d;
}

Engine_Ext_Lorentz_CUDA::Engine_Ext_Lorentz_CUDA(Operator_Ext_LorentzMaterial* op_ext, Engine_CUDA* eng) : Engine_Extension(op_ext)
{
	m_EngCuda = eng;
	// priority stays at the default, like the host version
	const int order = op_ext->GetDispersionOrder();
	const unsigned int Ny = eng->GetNumLines(1), Nz = eng->GetNumLines(2);

	m_Orders.resize(order);
	try
	{
		for (int o = 0; o < order; ++o)
		{
			Order& od = m_Orders[o];
			od.count = op_ext->m_LM_Count.at(o);
			if (od.count == 0)
				continue;

			std::vector<unsigned long long> cell(od.count);
			for (unsigned int i = 0; i < od.count; ++i)
			{
				const unsigned int* const* pos = op_ext->m_LM_pos[o];
				cell[i] = ((unsigned long long)pos[0][i] * Ny + pos[1][i]) * Nz + pos[2][i];
			}
			LOR_CUDA_CHECK(cudaMalloc((void**)&od.cell, od.count * sizeof(unsigned long long)));
			LOR_CUDA_CHECK(cudaMemcpy(od.cell, cell.data(), od.count * sizeof(unsigned long long), cudaMemcpyHostToDevice));

			od.volt.on = op_ext->m_volt_ADE_On[o];
			od.volt.lorOn = od.volt.on && op_ext->m_volt_Lor_ADE_On[o];
			if (od.volt.on)
			{
				od.volt.ade  = UploadVec3(NULL, o, od.count, true);
				od.volt.cInt = UploadVec3(op_ext->v_int_ADE, o, od.count, false);
				od.volt.cExt = UploadVec3(op_ext->v_ext_ADE, o, od.count, false);
				if (od.volt.lorOn)
				{
					od.volt.lor  = UploadVec3(NULL, o, od.count, true);
					od.volt.cLor = UploadVec3(op_ext->v_Lor_ADE, o, od.count, false);
				}
			}

			od.curr.on = op_ext->m_curr_ADE_On[o];
			od.curr.lorOn = od.curr.on && op_ext->m_curr_Lor_ADE_On[o];
			if (od.curr.on)
			{
				od.curr.ade  = UploadVec3(NULL, o, od.count, true);
				od.curr.cInt = UploadVec3(op_ext->i_int_ADE, o, od.count, false);
				od.curr.cExt = UploadVec3(op_ext->i_ext_ADE, o, od.count, false);
				if (od.curr.lorOn)
				{
					od.curr.lor  = UploadVec3(NULL, o, od.count, true);
					od.curr.cLor = UploadVec3(op_ext->i_Lor_ADE, o, od.count, false);
				}
			}
		}
	}
	catch (...)
	{
		Free();
		throw;
	}
}

Engine_Ext_Lorentz_CUDA::~Engine_Ext_Lorentz_CUDA()
{
	Free();
}

void Engine_Ext_Lorentz_CUDA::Free()
{
	for (size_t o = 0; o < m_Orders.size(); ++o)
	{
		Order& od = m_Orders[o];
		if (od.cell) cudaFree(od.cell);
		od.cell = NULL;
		Part* parts[2] = {&od.volt, &od.curr};
		for (int k = 0; k < 2; ++k)
		{
			float4** p[5] = {&parts[k]->ade, &parts[k]->lor, &parts[k]->cInt, &parts[k]->cExt, &parts[k]->cLor};
			for (int m = 0; m < 5; ++m)
			{
				if (*p[m]) cudaFree(*p[m]);
				*p[m] = NULL;
			}
		}
	}
}

std::string Engine_Ext_Lorentz_CUDA::GetExtensionName() const
{
	return Engine_Extension::GetExtensionName() + " (GPU)";
}

void Engine_Ext_Lorentz_CUDA::PreUpdate(float4* field, bool voltage)
{
	m_EngCuda->DeviceBegin();
	for (size_t o = 0; o < m_Orders.size(); ++o)
	{
		Order& od = m_Orders[o];
		Part& p = voltage ? od.volt : od.curr;
		if (!p.on || od.count == 0) continue;
		LOR_CUDA_CHECK(Lor_LaunchPre(field, od.cell, od.count, p.ade, p.lorOn ? p.lor : NULL, p.cLor, p.cInt, p.cExt));
	}
	// the pre update only reads the fields: the host mirror stays valid
}

void Engine_Ext_Lorentz_CUDA::Apply(float4* field, bool voltage)
{
	bool any = false;
	m_EngCuda->DeviceBegin();
	for (size_t o = 0; o < m_Orders.size(); ++o)
	{
		Order& od = m_Orders[o];
		Part& p = voltage ? od.volt : od.curr;
		if (!p.on || od.count == 0) continue;
		LOR_CUDA_CHECK(Lor_LaunchApply(field, od.cell, od.count, p.ade));
		any = true;
	}
	if (any)
		m_EngCuda->DeviceEnd();
}

void Engine_Ext_Lorentz_CUDA::DoPreVoltageUpdates() { PreUpdate(m_EngCuda->d_volt, true); }
void Engine_Ext_Lorentz_CUDA::DoPreCurrentUpdates() { PreUpdate(m_EngCuda->d_curr, false); }
void Engine_Ext_Lorentz_CUDA::Apply2Voltages()      { Apply(m_EngCuda->d_volt, true); }
void Engine_Ext_Lorentz_CUDA::Apply2Current()       { Apply(m_EngCuda->d_curr, false); }
