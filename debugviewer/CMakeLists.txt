project(debugviewer)
cmake_minimum_required(VERSION 3.17.0)

add_executable(${PROJECT_NAME} ${PROJECT_NAME}.cpp)
target_link_libraries(${PROJECT_NAME} PRIVATE opencv_core opencv_imgcodecs opencv_highgui)
target_compile_options(${PROJECT_NAME} PRIVATE ${PRIVATE_COMPILE_OPTIONS})
install(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
