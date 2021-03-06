#import <Cocoa/Cocoa.h>
#import <lua/lauxlib.h>
#import "../hammerspoon.h"
#import <sys/sysctl.h>
#import <sys/types.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <mach/host_info.h>
#import <mach/mach_host.h>
#import <mach/task_info.h>
#import <mach/task.h>

static NSHost *host;

/// hs.host.addresses() -> table
/// Function
/// Gets a list of network addresses for the current machine
///
/// Parameters:
///  * None
///
/// Returns:
///  * A table of strings containing the network addresses of the current machine
///
/// Notes:
///  * The results will include IPv4 and IPv6 addresses
static int hostAddresses(lua_State* L) {
    NSArray *addresses = [host addresses];
    if (!addresses) {
        lua_pushnil(L);
        return 1;
    }

    lua_newtable(L);
    int i = 1;
    for (NSString *address in addresses) {
        lua_pushinteger(L, i++);
        lua_pushstring(L, [address UTF8String]);
        lua_settable(L, -3);
    }

    return 1;
}

/// hs.host.names() -> table
/// Function
/// Gets a list of network names for the current machine
///
/// Parameters:
///  * None
///
/// Returns:
///  * A table of strings containing the network names of the current machine
///
/// Notes:
///  * This function should be used sparingly, as it may involve blocking network access to resolve hostnames
static int hostNames(lua_State* L) {
    NSArray *names = [host names];
    if (!names) {
        lua_pushnil(L);
        return 1;
    }

    lua_newtable(L);
    int i = 1;
    for (NSString *name in names) {
        lua_pushinteger(L, i++);
        lua_pushstring(L, [name UTF8String]);
        lua_settable(L, -3);
    }

    return 1;
}

/// hs.host.localizedName() -> string
/// Function
/// Gets the name of the current machine, as displayed in the Finder sidebar
///
/// Parameters:
///  * None
///
/// Returns:
///  * A string containing the name of the current machine
static int hostLocalizedName(lua_State* L) {
    lua_pushstring(L, [[host localizedName] UTF8String]);
    return 1;
}

/// hs.host.vmStat() -> table
/// Function
/// Returns a table containing virtual memory statistics for the current machine, as well as the page size (in bytes) and physical memory size (in bytes).
///
/// Parameters:
///  * None
///
/// Returns:
///  * A table containing the following keys:
///    * anonymousPages          -- the total number of pages that are anonymous
///    * cacheHits               -- number of object cache hits
///    * cacheLookups            -- number of object cache lookups
///    * fileBackedPages         -- the total number of pages that are file-backed (non-swap)
///    * memSize                 -- physical memory size in bytes
///    * pageIns                 -- the total number of requests for pages from a pager (such as the inode pager).
///    * pageOuts                -- the total number of pages that have been paged out.
///    * pageSize                -- page size in bytes
///    * pagesActive             -- the total number of pages currently in use and pageable.
///    * pagesCompressed         -- the total number of pages that have been compressed by the VM compressor.
///    * pagesCopyOnWrite        -- the number of faults that caused a page to be copied (generally caused by copy-on-write faults).
///    * pagesDecompressed       -- the total number of pages that have been decompressed by the VM compressor.
///    * pagesFree               -- the total number of free pages in the system.
///    * pagesInactive           -- the total number of pages on the inactive list.
///    * pagesPurgeable          -- the total number of purgeable pages.
///    * pagesPurged             -- the total number of pages that have been purged.
///    * pagesReactivated        -- the total number of pages that have been moved from the inactive list to the active list (reactivated).
///    * pagesSpeculative        -- the total number of pages on the speculative list.
///    * pagesThrottled          -- the total number of pages on the throttled list (not wired but not pageable).
///    * pagesUsedByVMCompressor -- the number of pages used to store compressed VM pages.
///    * pagesWiredDown          -- the total number of pages wired down. That is, pages that cannot be paged out.
///    * pagesZeroFilled         -- the total number of pages that have been zero-filled on demand.
///    * swapIns                 -- the total number of compressed pages that have been swapped out to disk.
///    * swapOuts                -- the total number of compressed pages that have been swapped back in from disk.
///    * translationFaults       -- the number of times the "vm_fault" routine has been called.
///    * uncompressedPages       -- the total number of pages (uncompressed) held within the compressor
///
/// Notes:
///  * Except for the addition of cacheHits, cacheLookups, pageSize and memSize, the results for this function should be identical to the OS X command `vm_stat`.
///  * Adapted primarily from the source code to Apple's vm_stat command located at http://www.opensource.apple.com/source/system_cmds/system_cmds-643.1.1/vm_stat.tproj/vm_stat.c
static int hs_vmstat(lua_State *L) {
    int mib[6];
    mib[0] = CTL_HW; mib[1] = HW_PAGESIZE;

    uint32_t pagesize;
    size_t length;
    length = sizeof (pagesize);
    if (sysctl (mib, 2, &pagesize, &length, NULL, 0) < 0) {
        char errStr[255] ;
        snprintf(errStr, 255, "Error getting page size (%d): %s", errno, strerror(errno)) ;
        showError(L, errStr) ;
        return 0 ;
    }

    mib[0] = CTL_HW; mib[1] = HW_MEMSIZE;
    uint64_t memsize;
    length = sizeof (memsize);
    if (sysctl (mib, 2, &memsize, &length, NULL, 0) < 0) {
        char errStr[255] ;
        snprintf(errStr, 255, "Error getting mem size (%d): %s", errno, strerror(errno)) ;
        showError(L, errStr) ;
        return 0 ;
    }

    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;

    vm_statistics64_data_t vm_stat;
    kern_return_t retVal = host_statistics64 (mach_host_self (), HOST_VM_INFO64, (host_info_t) &vm_stat, &count);

    if (retVal != KERN_SUCCESS) {
        char errStr[255] ;
        snprintf(errStr, 255, "Error getting VM Statistics: %s", mach_error_string(retVal)) ;
        showError(L, errStr) ;
        return 0 ;
    }

    lua_newtable(L) ;
        lua_pushinteger(L, (uint64_t) (vm_stat.free_count - vm_stat.speculative_count)) ; lua_setfield(L, -2, "pagesFree") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.active_count))                           ; lua_setfield(L, -2, "pagesActive") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.inactive_count))                         ; lua_setfield(L, -2, "pagesInactive") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.speculative_count))                      ; lua_setfield(L, -2, "pagesSpeculative") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.throttled_count))                        ; lua_setfield(L, -2, "pagesThrottled") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.wire_count))                             ; lua_setfield(L, -2, "pagesWiredDown") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.purgeable_count))                        ; lua_setfield(L, -2, "pagesPurgeable") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.faults))                                 ; lua_setfield(L, -2, "translationFaults") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.cow_faults))                             ; lua_setfield(L, -2, "pagesCopyOnWrite") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.zero_fill_count))                        ; lua_setfield(L, -2, "pagesZeroFilled") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.reactivations))                          ; lua_setfield(L, -2, "pagesReactivated") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.purges))                                 ; lua_setfield(L, -2, "pagesPurged") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.external_page_count))                    ; lua_setfield(L, -2, "fileBackedPages") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.internal_page_count))                    ; lua_setfield(L, -2, "anonymousPages") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.total_uncompressed_pages_in_compressor)) ; lua_setfield(L, -2, "uncompressedPages") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.compressor_page_count))                  ; lua_setfield(L, -2, "pagesUsedByVMCompressor") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.decompressions))                         ; lua_setfield(L, -2, "pagesDecompressed") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.compressions))                           ; lua_setfield(L, -2, "pagesCompressed") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.pageins))                                ; lua_setfield(L, -2, "pageIns") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.pageouts))                               ; lua_setfield(L, -2, "pageOuts") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.swapins))                                ; lua_setfield(L, -2, "swapIns") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.swapouts))                               ; lua_setfield(L, -2, "swapOuts") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.lookups))                                ; lua_setfield(L, -2, "cacheLookups") ;
        lua_pushinteger(L, (uint64_t) (vm_stat.hits))                                   ; lua_setfield(L, -2, "cacheHits") ;
        lua_pushinteger(L, (uint32_t) (pagesize))                                       ; lua_setfield(L, -2, "pageSize") ;
        lua_pushinteger(L, (uint64_t) (memsize))                                        ; lua_setfield(L, -2, "memSize") ;
    return 1 ;
}

/// hs.host.cpuUsage() -> table
/// Function
/// Returns a table containing cpu usage information for the current machine.
///
/// Parameters:
///  * None
///
/// Returns:
///  * An array of tables for each CPU core.  Each core's table will contain the following keys:
///    * user   -- percentage of CPU time occupied by user level processes.
///    * system -- percentage of CPU time occupied by system (kernel) level processes.
///    * nice   -- percentage of CPU time occupied by user level processes with a positive nice value (lower scheduling priority).
///    * active -- For convenience, when you just want percent in use, this is the sum of user, system, and nice.
///    * idle   -- percentage of CPU time spent idle
///
/// Notes:
///  * Adapted primarily from code found at http://stackoverflow.com/questions/6785069/get-cpu-percent-usage
static int hs_cpuInfo(lua_State *L) {
    unsigned numCPUs;

    int mib[2U] = { CTL_HW, HW_NCPU };
    size_t sizeOfNumCPUs = sizeof(numCPUs);
    int status = sysctl(mib, 2U, &numCPUs, &sizeOfNumCPUs, NULL, 0U);
    if(status) numCPUs = 1;  // On error, assume single cpu, single core

    processor_info_array_t cpuInfo ;
    mach_msg_type_number_t numCpuInfo ;
    natural_t numCPUsU = 0U;
    kern_return_t err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo);

    if(err == KERN_SUCCESS) {
// Sample code ran this on a timer and accessed variables outside of immediate name space. Assuming
// locking was to ensure another thread didn't change data out from underneath it and isn't necessary
// since we're doing a single snapshot with no retention (at this level) between checks..
//      See http://stackoverflow.com/questions/6785069/get-cpu-percent-usage
//         NSLock *CPUUsageLock = [[NSLock alloc] init];
//         [CPUUsageLock lock];
        lua_newtable(L) ;
        for(unsigned i = 0U; i < numCPUs; ++i) {
            float inUser   = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] ;
            float inSystem = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] ;
            float inNice   = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE] ;
            float inIdle   = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE] ;
            float inUse    = inUser + inSystem + inNice ;
            float total    = inUse + inIdle ;
            lua_newtable(L) ;
                lua_pushnumber(L, (  inUser / total) * 100) ; lua_setfield(L, -2, "user") ;
                lua_pushnumber(L, (inSystem / total) * 100) ; lua_setfield(L, -2, "system") ;
                lua_pushnumber(L, (  inNice / total) * 100) ; lua_setfield(L, -2, "nice") ;
                lua_pushnumber(L, (   inUse / total) * 100) ; lua_setfield(L, -2, "active") ;
                lua_pushnumber(L, (  inIdle / total) * 100) ; lua_setfield(L, -2, "idle") ;
            lua_rawseti(L, -2, luaL_len(L, -2) + 1);  // Insert this table at end of result table
        }
//         [CPUUsageLock unlock];
    } else {
        char errStr[255] ;
        snprintf(errStr, 255, "Error getting CPU Usage data: %s", mach_error_string(err)) ;
        showError(L, errStr) ;
        return 0 ;
    }
    return 1 ;
}

static const luaL_Reg hostlib[] = {
    {"addresses", hostAddresses},
    {"names", hostNames},
    {"localizedName", hostLocalizedName},
    {"vmStat", hs_vmstat},
    {"cpuUsage", hs_cpuInfo},

    {}
};

int luaopen_hs_host_internal(lua_State* L) {
    host = [NSHost currentHost];
    luaL_newlib(L, hostlib);

    return 1;
}
