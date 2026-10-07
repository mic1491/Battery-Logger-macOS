#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdint.h>
#include <string.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuLimit, gpuLimit, memoryLimit; } SMCPowerLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCPowerLimits limits;
    SMCKeyInfo keyInfo;
    uint8_t result, status, command;
    uint32_t data32;
    uint8_t bytes[32];
} SMCRequest;

static uint32_t fourcc(const char key[4]) {
    return ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) | (uint8_t)key[3];
}

static kern_return_t call_smc(io_connect_t connection, SMCRequest *input, SMCRequest *output) {
    size_t outputSize = sizeof(*output);
    return IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &outputSize);
}

int32_t BatteryLoggerReadCPUTemperature(double *temperature) {
    if (!temperature) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) return 0;

    SMCRequest input = {0}, output = {0};
    input.key = fourcc("TC0P");
    input.command = 9; /* read key metadata */
    result = call_smc(connection, &input, &output);
    uint32_t dataSize = output.keyInfo.size;
    uint32_t dataType = output.keyInfo.type;
    if (result == KERN_SUCCESS && dataSize >= 2 && dataSize <= 32) {
        memset(&input, 0, sizeof(input));
        memset(&output, 0, sizeof(output));
        input.key = fourcc("TC0P");
        input.keyInfo.size = dataSize;
        input.command = 5; /* read key bytes */
        result = call_smc(connection, &input, &output);
    }
    if (result == KERN_SUCCESS && dataSize >= 2) {
        if (dataType == fourcc("sp78")) {
            int16_t fixed = (int16_t)(((uint16_t)output.bytes[0] << 8) | output.bytes[1]);
            *temperature = (double)fixed / 256.0;
            result = (*temperature >= 0.0 && *temperature <= 120.0) ? KERN_SUCCESS : KERN_FAILURE;
        } else if (dataType == fourcc("flt ") && dataSize >= 4) {
            float decoded;
            memcpy(&decoded, output.bytes, sizeof(decoded));
            *temperature = decoded;
            result = (*temperature >= 0.0 && *temperature <= 120.0) ? KERN_SUCCESS : KERN_FAILURE;
        } else {
            result = KERN_FAILURE;
        }
    }
    IOServiceClose(connection);
    return result == KERN_SUCCESS ? 1 : 0;
}

int32_t BatteryLoggerReadChargeLimit(int32_t *limit) {
    if (!limit) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) return 0;

    SMCRequest input = {0}, output = {0};
    input.key = fourcc("BCLM");
    input.command = 9; /* read key metadata */
    result = call_smc(connection, &input, &output);
    if (result == KERN_SUCCESS && output.keyInfo.size == 1) {
        memset(&input, 0, sizeof(input));
        memset(&output, 0, sizeof(output));
        input.key = fourcc("BCLM");
        input.keyInfo.size = 1;
        input.command = 5; /* read key bytes */
        result = call_smc(connection, &input, &output);
        if (result == KERN_SUCCESS && output.result == 0) {
            *limit = (int32_t)output.bytes[0];
            IOServiceClose(connection);
            return 1;
        }
    }
    IOServiceClose(connection);
    return 0;
}
