cmake_minimum_required(VERSION 3.20.0)

# Repo root contains dts/bindings/ — tell Zephyr to search it for out-of-tree bindings.
list(APPEND DTS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(pic64_smp_hello)

# Shared hardware drivers (relative to this demo directory)
set(DRIVERS "${CMAKE_CURRENT_SOURCE_DIR}/../../drivers")

target_sources(app PRIVATE
    src/main.c
    src/ui.c
    src/demo_manager.c
    src/screen_hud.c
    src/screen_dashboard.c
    src/screen_charts.c
    src/screen_widgets.c
    src/microchip_logo_img.c
    src/screen_game.c
    ${DRIVERS}/vdma_disp/vdma_disp.c
    ${DRIVERS}/hdmi_fb/hdmi_fb.c
)

# hdmi_fb.c includes vdma_disp.h — expose both driver directories
target_include_directories(app PRIVATE
    src
    ${DRIVERS}/vdma_disp
    ${DRIVERS}/hdmi_fb
)

target_link_libraries(app PRIVATE m)
