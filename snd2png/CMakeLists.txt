project(snd2png CXX)
cmake_minimum_required(VERSION 3.3.0)

add_executable(${PROJECT_NAME} ${PROJECT_NAME}.cpp)

pkg_check_modules(FFTW3 fftw3)
pkg_check_modules(SNDFILE sndfile)

target_link_libraries(${PROJECT_NAME} PRIVATE opencv_core opencv_imgcodecs ${FFTW3_LIBRARIES} ${SNDFILE_LIBRARIES})
target_include_directories(${PROJECT_NAME} PRIVATE ${FFTW3_INCLUDE_DIRS} ${SNDFILE_INCLUDE_DIRS})
target_compile_options(${PROJECT_NAME} PRIVATE ${FFTW3_CFLAGS} ${SNDFILE_CFLAGS})
target_link_options(${PROJECT_NAME} PRIVATE ${FFTW3_LDFLAGS} ${SNDFILE_LDFLAGS})
install(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
