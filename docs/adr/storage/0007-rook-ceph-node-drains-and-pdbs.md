# 0007. Disable Rook-managed PDBs to unblock node drains

## Status

Accepted

## Context

Confirmed live: draining a node with 2 of 3 mons dropped quorum, and the
operator-managed mon PodDisruptionBudget then refused to also evict the 3rd —
correctly, but it stalled the drain and needed a manual uncordon to unstick.

## Decision

Accepted tradeoff given the current 2-node hardware constraint (see
[0006](0006-rook-ceph-topology-and-local-path-interim.md)): `disruptionManagement.
managePodBudgets: false` lets drains proceed and accepts brief storage unavailability
rather than having Rook's PDBs block node maintenance.

## Consequences

Node drains can now proceed without manual intervention, but Rook no longer guarantees
mon/OSD quorum is preserved during a drain — a drain can cause a brief storage outage.
Revisit once there are enough nodes that Rook's own PDB logic wouldn't need to block a
drain in the first place.
