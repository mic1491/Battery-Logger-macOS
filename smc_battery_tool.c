#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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

static int read_bclm(io_connect_t conn) {
    SMCRequest input = {0}, output = {0};
    input.key = fourcc("BCLM");
    input.keyInfo.size = 1;
    input.command = 5; /* read */
    kern_return_t res = call_smc(conn, &input, &output);
    if (res == KERN_SUCCESS && output.result == 0) {
        return (int)output.bytes[0];
    }
    return -1;
}

static int write_bclm(io_connect_t conn, int limit) {
    if (limit < 50 || limit > 100) return -2;
    SMCRequest input = {0}, output = {0};
    input.key = fourcc("BCLM");
    input.keyInfo.size = 1;
    input.command = 6; /* write */
    input.bytes[0] = (uint8_t)limit;
    kern_return_t res = call_smc(conn, &input, &output);
    if (res == KERN_SUCCESS && output.result == 0) {
        return 0;
    }
    return (int)res;
}

int main(int argc, char *argv[]) {
    setuid(0);
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) { fprintf(stderr, "AppleSMC not found\n"); return 1; }
    io_connect_t conn = IO_OBJECT_NULL;
    if (IOServiceOpen(service, mach_task_self(), 0, &conn) != KERN_SUCCESS) {
        fprintf(stderr, "Failed to open AppleSMC\n");
        return 1;
    }
    IOObjectRelease(service);

    if (argc >= 2 && strcmp(argv[1], "read") == 0) {
        int val = read_bclm(conn);
        printf("%d\n", val);
        IOServiceClose(conn);
        return val >= 0 ? 0 : 2;
    } else if (argc >= 3 && strcmp(argv[1], "write") == 0) {
        int target = atoi(argv[2]);
        int res = write_bclm(conn, target);
        if (res == 0) {
            printf("OK: BCLM set to %d%%\n", target);
            IOServiceClose(conn);
            return 0;
        } else {
            fprintf(stderr, "Failed to write BCLM (code %d)\n", res);
            IOServiceClose(conn);
            return 3;
        }
    } else {
        printf("Usage: smc_battery_tool read | write <50..100>\n");
        IOServiceClose(conn);
        return 1;
    }
}
