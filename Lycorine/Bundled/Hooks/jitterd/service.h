#pragma once
#include <mach/mach.h>

kern_return_t service_publish(mach_port_t service);
void service_receive(mach_port_t service);
