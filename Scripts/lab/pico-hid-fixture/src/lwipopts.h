#ifndef KEYPATH_LWIPOPTS_H
#define KEYPATH_LWIPOPTS_H

// Raw lwIP configuration for the Pico SDK's polling CYW43 integration. The
// fixture exposes one small HTTP control server and deliberately has no socket
// or netconn compatibility layer.
#define NO_SYS 1
#define SYS_LIGHTWEIGHT_PROT 0

#define LWIP_RAW 1
#define LWIP_TCP 1
#define LWIP_UDP 1
#define LWIP_DHCP 1
#define LWIP_DNS 1
#define LWIP_IGMP 1
#define LWIP_SOCKET 0
#define LWIP_NETCONN 0

#define LWIP_NETIF_HOSTNAME 1
#define LWIP_NETIF_STATUS_CALLBACK 1
#define LWIP_NETIF_LINK_CALLBACK 1
#define LWIP_DHCP_DOES_ACD_CHECK 0
#define LWIP_MDNS_RESPONDER 1
#define LWIP_NUM_NETIF_CLIENT_DATA 1
#define MDNS_MAX_SERVICES 1

#define MEM_ALIGNMENT 4
#define MEM_SIZE 16000
#define MEMP_NUM_TCP_PCB 4
#define MEMP_NUM_TCP_PCB_LISTEN 2
#define MEMP_NUM_TCP_SEG 16

#define TCP_MSS 1460
#define TCP_WND (4 * TCP_MSS)
#define TCP_SND_BUF (4 * TCP_MSS)
#define TCP_QUEUE_OOSEQ 0

#define LWIP_CHKSUM_ALGORITHM 3

#endif
