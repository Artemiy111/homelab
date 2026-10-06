# Alloy Profiler

Alloy в режиме eBPF-сэмплирования профилей. Снимает стеки процессов в
контейнерах своей ноды и отправляет их в `apps/pyroscope`.

## Почему не в apps/alloy

Действующий Alloy-пайплайн логов намеренно hardened: `runAsNonRoot: true`,
`drop: ["ALL"]`, `allowPrivilegeEscalation: false`, без root и hostPath. Он
читает логи всех подов, и ослаблять его нельзя. eBPF-сэмплирование требует
root (perf_event_open, чтение `/proc/<pid>/stack` и maps чужих процессов) и
CAP_SYS_ADMIN, поэтому это отдельный инстанс.

Привилегии взяты по списку capabilities (как у Beyla в #542), а не
`privileged: true` из примера Pyroscope.

## bpffs

`/sys/fs/bpf` смонтирован с `mountPropagation: HostToContainer` и делится с
Beyla. Нужен, чтобы pinned BPF-карты были едиными — без них не работает
связка «трейс → профиль» (Beyla в этом случае пишет `OBI will use
process-internal maps`).
