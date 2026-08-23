# 0006. Rook-Ceph hardware topology, `replicated.size`, and the local-path-provisioner interim

## Status

Accepted

## Context

Rook-Ceph's normal topology is a dedicated raw block device per node for OSDs — it only
claims genuinely free/unpartitioned space, so at worst it comes up with zero usable OSDs
(not destructive to the Talos install) rather than fighting the OS for its disk.
**Current real hardware**: `home-ops-1` (HP ProDesk 600 G4 Mini) has one 256GB NVMe,
entirely consumed by the Talos install, zero spare block device, contributing no OSD.
`home-ops-2` (a repurposed laptop) has a spare 1TB HDD (`/dev/sda`) wiped and handed to
Rook via `useAllDevices: true` — the only OSD in the cluster right now. With a single OSD
host, `failureDomain: host` can only ever place 1 replica, so `mgr`/`mon`/`osd` resource
requests are scaled well below common upstream examples (often 8Gi+) to fit this
hardware — revisit once real usage is known (`ceph osd df`).

## Decision

`cephBlockPools` is deliberately `replicated.size: 1` (data-loss risk, single point of
failure) rather than the usual 3 — bump back up (2 once `home-ops-1` gets a second disk,
3 once a 3rd OSD host exists) per docs/planning/HARDWARE_PLAN.md's node-2 notes. Same reason this can't
be validated on the local dev cluster: Docker-provisioned Talos nodes have no raw block
devices available either, so CephCluster will likely stay unhealthy there — that's
expected, not a bug (see README.md's local-cluster caveats). `mon.allowMultiplePerNode:
true` is required for the local single-node dev cluster (Rook refuses to schedule 3 mons
on fewer than 3 nodes otherwise, permanently blocking the HelmRelease's `--wait`) and is
harmless to also carry into the real multi-node config — Rook still prefers spreading
mons across distinct nodes when enough exist, this only removes the hard block for when
there aren't enough.

**Interim answer while Rook-Ceph has no usable OSDs on `home-ops-1`:**
`kubernetes/apps/kube-system/local-path-provisioner` -- node-local hostPath storage
(single replica, no HA/replication/snapshots). Set as the cluster default `StorageClass`
(`local-path`); `ceph-block`'s `isDefault` is flipped to `false` in the same change,
since two default StorageClasses is invalid/ambiguous -- the two flip back together once
`ceph-block` is trusted enough to be the default. This is explicitly an amendment, not a
replacement, of the Rook-Ceph decision in `docs/planning/PROJECT_BRIEF.md`'s decision table -- see that
file and `docs/runbooks/cluster-bootstrap.md`.

Deployed via bjw-s's `app-template` (`oci://ghcr.io/bjw-s-labs/helm/app-template`), not a
third-party community chart -- Rancher doesn't publish an official chart itself
(rancher/local-path-provisioner#89), and the alternatives are all single-maintainer
wrappers. RBAC (ClusterRole/ClusterRoleBinding/Role/RoleBinding), the `config.json`
node-path map, and the `StorageClass` itself are hand-written as `extraObjects`,
transcribed 1:1 from upstream's own raw deploy manifest
(rancher/local-path-provisioner `deploy/local-path-storage.yaml`) rather than depending
on anyone's packaging of it.

## Consequences

A single-OSD, `replicated.size: 1` pool has no redundancy — losing `home-ops-2`'s HDD
loses the data on `ceph-block`. `local-path` remains the cluster default StorageClass
until `ceph-block` is trusted enough to take over. See also
[0008](0008-rook-ceph-muted-health-warnings.md) for the health-check warnings this
topology permanently trips, and [0007](0007-rook-ceph-node-drains-and-pdbs.md) for the
node-drain implications of a 2-node/3-mon cluster.
