#ifndef ENGINE_EXT_LORENTZ_CUDA_H
#define ENGINE_EXT_LORENTZ_CUDA_H

#include <string>
#include <vector>
#include "extensions/engine_extension.h"
#include "lorentz_kernels_cuda.h"

class Operator_Ext_LorentzMaterial;
class Engine_CUDA;

//! Drude/Lorentz (ADE) material extension on the GPU; also does the Conducting Sheet extension
//! (Operator_Ext_ConductingSheet is a Lorentz extension). ADE states and coefficients live on the GPU.
class Engine_Ext_Lorentz_CUDA : public Engine_Extension
{
public:
	Engine_Ext_Lorentz_CUDA(Operator_Ext_LorentzMaterial* op_ext, Engine_CUDA* eng);
	virtual ~Engine_Ext_Lorentz_CUDA();

	virtual void DoPreVoltageUpdates();
	virtual void Apply2Voltages();
	virtual void DoPreCurrentUpdates();
	virtual void Apply2Current();

	virtual std::string GetExtensionName() const;

private:
	//! data of one dispersion order; the voltage and the current part are independent
	struct Part
	{
		bool on;      //!< ADE active (m_volt_ADE_On / m_curr_ADE_On)
		bool lorOn;   //!< additional Lorentz term
		float4* ade;  float4* lor;
		float4* cInt; float4* cExt; float4* cLor;
		Part() : on(false), lorOn(false), ade(0), lor(0), cInt(0), cExt(0), cLor(0) {}
	};
	struct Order
	{
		unsigned int count;
		unsigned long long* cell;
		Part volt, curr;
		Order() : count(0), cell(0) {}
	};

	Engine_CUDA* m_EngCuda;
	std::vector<Order> m_Orders;

	void Free();
	void PreUpdate(float4* field, bool voltage);
	void Apply(float4* field, bool voltage);
};

#endif // ENGINE_EXT_LORENTZ_CUDA_H
