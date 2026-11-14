
if (WITH_MPI)
  set(MPI_SOURCES
     ${CMAKE_CURRENT_SOURCE_DIR}/openems_fdtd_mpi.cpp
     ${CMAKE_CURRENT_SOURCE_DIR}/operator_mpi.cpp
     ${CMAKE_CURRENT_SOURCE_DIR}/engine_mpi.cpp
     )
endif()

if(${WITH_CUDA})
  set(CUDA_SOURCES
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/engine_cuda.cu
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/operator_cuda.cpp
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/upml_kernels_cuda.cu
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/engine_ext_upml_cuda.cpp
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/engine_cuda_ext.cpp
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/excitation_kernels_cuda.cu
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/engine_ext_excitation_cuda.cpp
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/lorentz_kernels_cuda.cu
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/engine_ext_lorentz_cuda.cpp
    ${PROJECT_SOURCE_DIR}/FDTD_CUDA/engine_interface_cuda.cpp
  )
endif()

set(SOURCES
  ${SOURCES}
  ${MPI_SOURCES}
  ${CUDA_SOURCES}
  ${CMAKE_CURRENT_SOURCE_DIR}/engine.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/operator.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/engine_multithread.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/operator_cylinder.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/engine_cylinder.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/engine_sse.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/operator_sse.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/operator_sse_compressed.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/engine_sse_compressed.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/operator_multithread.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/excitation.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/operator_cylindermultigrid.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/engine_cylindermultigrid.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/engine_interface_fdtd.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/engine_interface_sse_fdtd.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/engine_interface_cylindrical_fdtd.cpp
  PARENT_SCOPE
)
