project(systemd)
cmake_minimum_required(VERSION 3.17.0)

set(pkglibexecdir "${CMAKE_INSTALL_PREFIX}/${OS_AUTOINST_DATA_DIR}")
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/os-autoinst-openvswitch.service.in"
    "${CMAKE_CURRENT_BINARY_DIR}/os-autoinst-openvswitch.service"
)
install(
    FILES "${CMAKE_CURRENT_BINARY_DIR}/os-autoinst-openvswitch.service"
    DESTINATION "${SYSTEMD_SERVICE_DIR}"
    COMPONENT "openvswitch"
    EXCLUDE_FROM_ALL
)
