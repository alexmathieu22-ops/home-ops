# Homelab Hardware Plan

Prices are USD street price as of mid-2026 unless noted; **Canadian pricing typically runs
30–40% higher** on imported mini PCs due to exchange rate + import costs — budget accordingly
for elsewhere. All tiers assume **3 nodes minimum** (etcd quorum for Talos HA) and an apartment
setting, so noise and power draw matter as much as raw specs.

---

## The decisions that matter more than which mini PC

1. **Mini PCs, not a used enterprise server.** A decade-old Dell/HP rack server is the classic
   "$1,200 mistake" — loud (unusable in an apartment bedroom/living room), power-hungry
   (100–300W idle vs. 6–20W for a modern mini PC), and no longer actually cheaper once you
   account for electricity over 2–3 years. Skip this path entirely.
2. **3 identical nodes > 1 big node + 2 small ones.** Uniform hardware makes Talos/Ceph/Longhorn
   configuration trivial and avoids scheduling headaches. Buy the same model three times.
3. **Rack is optional, not required.** A 10-inch "mini rack" (DeskPi RackMate / GeeekPi, an
   ecosystem popularized by Jeff Geerling) is genuinely nice for cable management once you have
   a switch + 3 nodes + a NAS, but a $30 shelf works too. Don't let rack shopping delay the
   actual build.
4. **Decide storage split early**: cluster nodes carry OS + Longhorn app-state on NVMe; bulk
   media (photos/video libraries) goes on a separate NAS, not replicated in-cluster storage.

---

## Your pick: simple, clean, under CAD $1,000

Given you want to start small in an apartment, here's the concrete shopping list — this is
Tier 1 below, tightened to a single clear recommendation rather than a range of options:

| Item            | Pick                                          | Price (CAD)      |
| --------------- | --------------------------------------------- | ---------------- |
| 3× compute node | Beelink EQ12 Pro (N100, 16GB RAM, 500GB NVMe) | ~$230 × 3 = $690 |
| Switch          | 5-port unmanaged 2.5GbE switch                | ~$45             |
| Cabling         | 3× short Cat6 cables                          | ~$15             |
| **Total**       |                                               | **~$750**        |

That leaves ~$250 of your $1,000 budget unspent — hold onto it rather than pre-buying a NAS or
rack: use Longhorn on the nodes' own NVMe for app state to start, and revisit storage once you
know what you're actually missing (almost certainly "more space for Immich," at which point a
2-bay NAS becomes an easy, well-justified add rather than a guess).

**Why this over the individual N100 boxes from the earlier list**: EQ12 Pro specifically pairs a
genuinely tiny footprint (fits in one hand, stacks three-high with zero cable mess) with 16GB
RAM and NVMe as standard — no rack needed, no separate shelf needed, easy to tuck onto a
bookshelf or behind a TV. This is the "small and clean" brief taken literally.

**Honest limitation to plan around**: 16GB × 3 nodes is enough for the full infra layer
(Cilium/cert-manager/ESO/Longhorn/Envoy Gateway) plus a handful of apps, but you'll likely feel
it once Immich's ML features and 3–4 more apps are all running concurrently. That's fine — it's
a $750 way to prove the entire architecture end-to-end, and RAM/an extra node is a cheap,
isolated upgrade later that doesn't invalidate anything in the E2E plan.

---

## Tier 1 — Budget (~CAD $700–1,000 total)

**Compute:** 3× Intel N100 mini PCs (Beelink EQ12 Pro or similar) — 4-core, 16GB RAM, 500GB
NVMe, single 2.5GbE, ~6W idle. ~$220–260 CAD each.

**Networking:** Existing router + an unmanaged 5-port 2.5GbE switch (~$40 CAD).

**Storage:** No dedicated NAS yet — use a USB3 external drive or a 4th N100 box as
NFS/Longhorn-only storage node; add a real NAS later.

**Rack:** Skip it — a $25 wire shelf or even just stacked on a desk with a cable tie or two.

| Pros                                                  | Cons                                                                                                                                                   |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Cheapest real entry into a 3-node HA Talos cluster    | N100 has no hardware transcode headroom for Jellyfin 4K, limited ML performance for Immich face-recognition                                            |
| 6W idle × 3 ≈ negligible electricity cost             | Single 2.5GbE NIC — fine for K8s traffic, not for a storage-heavy Ceph setup                                                                           |
| Silent, small, apartment-friendly                     | 16GB RAM is tight once you're running Cilium + cert-manager + ESO + Longhorn + 4–5 apps simultaneously — expect to feel the ceiling within 6–12 months |
| Enough to fully validate the GitOps/Talos/VPN pattern | No PCIe/expansion — what you buy is what you get, forever                                                                                              |

**Verdict:** great for proving the architecture cheaply, but you will likely outgrow the RAM
ceiling once Immich, Home Assistant, Paperless-ngx, and monitoring are all running together.
Reasonable if budget is the hard constraint right now and you're fine buying again in a year.

---

## Tier 2 — Mid-range / recommended (~CAD $2,000–2,600 total)

**Compute:** 3× Beelink SER8 or SER9 (Ryzen 7 8845HS/H255, 8-core, Radeon 780M iGPU, 32GB DDR5,
1TB NVMe, single 2.5GbE) — ~$650–700 CAD each. Alternative: 3× Minisforum MS-01 (i5/i9-12/13th
gen, dual 10GbE SFP+ + dual 2.5GbE, PCIe slot, 3× M.2) at a similar or slightly higher price —
the networking headroom is the differentiator.

**Networking:** Managed 2.5GbE switch (Mikrotik CRS or similar, ~$150–200 CAD) — needed once you
want VLANs (separate IoT/smart-home traffic from cluster/management traffic, which you'll want
once Home Assistant + Zigbee/Matter devices are in the picture).

**Storage:** A small dedicated NAS (Synology DS223/DS224+ or a DIY TrueNAS box, 2-bay, ~2×4TB
mirrored) for photo/media libraries — ~$500–700 CAD. Cluster nodes' NVMe handles Longhorn
app-state only.

**Rack:** DeskPi RackMate T1 (8U, 10-inch) or T0 (4U) — ~$150–250 CAD including a couple of
accessory shelves for the NAS and switch. Genuinely nice for a 3-node + switch + NAS build; not
mandatory but this is the tier where it starts paying for itself in sanity.

| Pros                                                                                      | Cons                                                                |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Radeon 780M iGPU gives real hardware transcoding for Jellyfin                             | Still single 2.5GbE on SER8/9 unless you pick the MS-01             |
| 32GB RAM per node — comfortable for the full infra + app stack from Phase 5–8 of the plan | ~2–3× the cost of Tier 1                                            |
| Good multi-year headroom without feeling cramped                                          | MS-01's dual 10GbE is wasted unless your NAS/switch also support it |
| Quiet, low power (12–20W idle per node)                                                   |                                                                     |

**Verdict — this is where I'd point you.** It matches what you're actually building (a real
Kubernetes platform with Cilium/Envoy Gateway/ESO/Longhorn/observability all running
concurrently, plus Immich's ML workload and Jellyfin transcoding), has genuine multi-year
headroom, and stays apartment-appropriate on noise and power. If choosing between SER8/9 and
MS-01: pick **MS-01** if you think you'll ever want Ceph or a dedicated 10GbE storage path;
pick **SER8/9** if you want the iGPU for transcoding and don't care about 10GbE.

---

## Tier 3 — Performance / grow-into-it (~CAD $4,000–5,500 total)

**Compute:** 3× Minisforum MS-A2 (Ryzen 9 8945HS/HX, 16-core options available, dual 2.5GbE +
10GbE, dual/triple NVMe) — ~$900–1,100 CAD each, or a mixed setup with one MS-A2 "storage/AI"
node plus 2× MS-01 for compute.

**Networking:** Managed switch with real 10GbE uplinks (Mikrotik CRS309 or similar,
~$350–450 CAD) to actually use the nodes' 10GbE ports.

**Storage:** 4-bay NAS (Synology DS923+/DS1522+ or TrueNAS DIY) with 4×8TB in RAID/ZFS,
~$1,200–1,600 CAD, connected over 10GbE.

**Rack:** Full 10-inch rack build with PDU, patch panel, UPS shelf — ~$400–600 CAD.

**UPS:** Don't skip this at this spend level — a rack-mountable or standalone UPS
(CyberPower/APC, ~$200–300 CAD) protects against the etcd-corruption risk of unclean shutdowns
across 3 nodes simultaneously.

| Pros                                                                                                                               | Cons                                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Real 10GbE throughout — Ceph/Rook becomes genuinely fast, not just "works"                                                         | Meaningfully more money for headroom you may not use for 1–2 years                                              |
| 16-core nodes give room for local AI/ML workloads (local LLM inference, Frigate NVR, heavier Immich ML) alongside the K8s platform | Higher idle power draw (20–35W/node) — still apartment-fine, but noticeable on the electricity bill vs Tier 1/2 |
| Genuinely "won't need to upgrade for years"                                                                                        | Overkill for a first build if you haven't yet felt Tier 2's limits                                              |

**Verdict:** only go here if you already know you want local AI workloads (self-hosted LLM
inference, Frigate camera NVR with object detection) alongside the platform-engineering side —
otherwise you're pre-paying for headroom Tier 2 won't make you miss for a long time.

---

## My recommendation

**Start at Tier 2** (3× Beelink SER8/9 or Minisforum MS-01, small managed switch, 2-bay NAS,
optional DeskPi rack). It's sized correctly for everything in the E2E plan — the full
Cilium/Envoy Gateway/ESO/Longhorn/observability stack plus a realistic app list — without
over-buying, and the incremental cost over Tier 1 buys you real multi-year headroom rather than
a near-term repurchase. Add the UPS from Tier 3's list regardless of which tier you land on —
it's cheap insurance against etcd corruption from a bad power blip, and apartments lose power
more often than people expect.

Buy the rack last, after you've lived with the setup for a few weeks and know how much you
actually want to tidy up — it's the one line item with zero functional impact on the cluster.
