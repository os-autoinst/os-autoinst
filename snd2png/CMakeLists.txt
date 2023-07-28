project(snd2png CXX)
cmake_minimum_required(VERSION 3.17.0)

add_executable(${PROJECT_NAME} ${PROJECT_NAME}.cpp)
target_link_libraries(${PROJECT_NAME} PRIVATE opencv_core opencv_imgcodecs)
target_compile_options(${PROJECT_NAME} PRIVATE ${PRIVATE_COMPILE_OPTIONS})
target_use_pkg_config_module(${PROJECT_NAME} "fftw3")
target_use_pkg_config_module(${PROJECT_NAME} "sndfile")
install(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
