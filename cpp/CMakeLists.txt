cmake_minimum_required(VERSION 3.16)

project(gpu_dv_cpp VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(trace_parser
     trace_parser/src/main.cpp
)

add_executable(coverage_extract
     coverage_extract/src/main.cpp
)
