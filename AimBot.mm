#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/task.h>
#include <mach/vm_map.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <QuartzCore/QuartzCore.h>

#define TARGET_NAME "FreeFire"
#define OFFSET_LOCAL_PLAYER 0x00A1B2C3
#define OFFSET_ENTITY_LIST 0x00D4E5F6
#define OFFSET_VIEW_MATRIX 0x00G7H8I9
#define OFFSET_ENTITY_COUNT 0x00J0K1L2
#define OFFSET_VIEW_ANGLES 0x00M3N4O5
#define OFFSET_ANTICHEAT_FLAG1 0x00P6Q7R8
#define OFFSET_ANTICHEAT_FLAG2 0x00S9T0U1
#define SCREEN_WIDTH 1920
#define SCREEN_HEIGHT 1080

typedef struct {
    float x, y, z;
    float pitch, yaw;
    float distance;
    int health;
    int teamID;
    int isAlive;
} Entity;

typedef struct {
    float m[16];
} Matrix4x4;

task_t target_task = MACH_PORT_NULL;
mach_vm_address_t base_address = 0;

kern_return_t read_memory(mach_vm_address_t address, void *buffer, size_t size) {
    mach_vm_size_t out_size = 0;
    return mach_vm_read_overwrite(target_task, address, size, (mach_vm_address_t)buffer, &out_size);
}

kern_return_t write_memory(mach_vm_address_t address, void *buffer, size_t size) {
    return mach_vm_write(target_task, address, (vm_offset_t)buffer, size);
}

pid_t get_process_pid(const char *name) {
    return 1234;
}

mach_vm_address_t get_base_address(pid_t pid) {
    return 0x100000000;
}

CGPoint world_to_screen(Entity *ent, Matrix4x4 *viewMatrix) {
    CGPoint screen = {0, 0};
    float w = viewMatrix->m[3] * ent->x + viewMatrix->m[7] * ent->y + viewMatrix->m[11] * ent->z + viewMatrix->m[15];
    if (w < 0.001f) return screen;
    float x = viewMatrix->m[0] * ent->x + viewMatrix->m[4] * ent->y + viewMatrix->m[8] * ent->z + viewMatrix->m[12];
    float y = viewMatrix->m[1] * ent->x + viewMatrix->m[5] * ent->y + viewMatrix->m[9] * ent->z + viewMatrix->m[13];
    screen.x = (x / w + 1.0f) * 0.5f * SCREEN_WIDTH;
    screen.y = (1.0f - (y / w + 1.0f) * 0.5f) * SCREEN_HEIGHT;
    return screen;
}

void aimlock(Entity *target, Entity *localPlayer) {
    if (!target || !localPlayer) return;
    float dx = target->x - localPlayer->x;
    float dy = target->y - localPlayer->y;
    float dz = target->z - localPlayer->z;
    float pitch = atan2(dy, sqrt(dx*dx + dz*dz)) * 180.0f / M_PI;
    float yaw = atan2(dx, dz) * 180.0f / M_PI;
    write_memory(base_address + OFFSET_VIEW_ANGLES, &pitch, sizeof(float));
    write_memory(base_address + OFFSET_VIEW_ANGLES + 4, &yaw, sizeof(float));
}

void clean_traces() {
    int null_val = 0;
    write_memory(base_address + OFFSET_ANTICHEAT_FLAG1, &null_val, 4);
    write_memory(base_address + OFFSET_ANTICHEAT_FLAG2, &null_val, 4);
}

void bypass_anticheat() {
    char *sandbox = "/usr/lib/sandbox";
    char *null_ptr = NULL;
    write_memory((mach_vm_address_t)sandbox, &null_ptr, sizeof(null_ptr));
    syscall(26, 0, 0, 0);
}

int main(int argc, char **argv) {
    pid_t pid = get_process_pid(TARGET_NAME);
    if (!pid) {
        printf("[-] Khong tim thay FreeFire\n");
        return 1;
    }
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &target_task);
    if (kr != KERN_SUCCESS) {
        printf("[-] task_for_pid that bai\n");
        return 1;
    }
    base_address = get_base_address(pid);
    if (!base_address) {
        printf("[-] Khong tim thay base address\n");
        return 1;
    }
    printf("[+] Attach thanh cong: PID %d, Base 0x%llx\n", pid, base_address);
    Matrix4x4 viewMatrix;
    while (1) {
        Entity local;
        read_memory(base_address + OFFSET_LOCAL_PLAYER, &local, sizeof(Entity));
        if (!local.isAlive) {
            usleep(50000);
            continue;
        }
        int entityCount = 0;
        read_memory(base_address + OFFSET_ENTITY_COUNT, &entityCount, sizeof(int));
        if (entityCount <= 0 || entityCount > 100) {
            usleep(50000);
            continue;
        }
        Entity *entities = malloc(entityCount * sizeof(Entity));
        read_memory(base_address + OFFSET_ENTITY_LIST, entities, entityCount * sizeof(Entity));
        Entity *bestTarget = NULL;
        float minDist = 9999.0f;
        for (int i = 0; i < entityCount; i++) {
            if (entities[i].isAlive && entities[i].teamID != local.teamID && entities[i].health > 0) {
                float dx = entities[i].x - local.x;
                float dy = entities[i].y - local.y;
                float dz = entities[i].z - local.z;
                float dist = sqrt(dx*dx + dy*dy + dz*dz);
                if (dist < minDist && dist < 200.0f) {
                    minDist = dist;
                    bestTarget = &entities[i];
                }
            }
        }
        if (bestTarget) {
            aimlock(bestTarget, &local);
            clean_traces();
            bypass_anticheat();
        }
        free(entities);
        usleep(8000);
    }
    return 0;
}
