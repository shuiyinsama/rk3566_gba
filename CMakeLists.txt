cmake_minimum_required(VERSION 3.16)

project(
  rk3566_gba
  VERSION 0.2.0
  DESCRIPTION "RK3566 handheld validation project"
  LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(rk3566-gba
  src/main.cpp
)

target_compile_features(rk3566-gba PRIVATE cxx_std_17)

if(MSVC)
  target_compile_options(rk3566-gba PRIVATE /W4)
else()
  target_compile_options(rk3566-gba PRIVATE -Wall -Wextra -Wpedantic)
endif()

install(TARGETS rk3566-gba RUNTIME DESTINATION bin)

include(CTest)
if(BUILD_TESTING)
  add_test(NAME rk3566-gba-help COMMAND rk3566-gba --help)
  add_test(NAME rk3566-gba-version COMMAND rk3566-gba --version)
  add_test(NAME rk3566-gba-checklist COMMAND rk3566-gba --checklist)
  add_test(NAME rk3566-gba-system-commands COMMAND rk3566-gba --system-commands)
endif()
 