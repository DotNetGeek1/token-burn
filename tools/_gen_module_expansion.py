#!/usr/bin/env python3
"""One-shot generator for the Token Burn module expansion catalogue."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def cond(left, op, right):
    return {"left": left, "operator": op, "right": right}


def effect(op, target, value, conditions=None):
    out = {"operation": op, "target": target, "value": value}
    if conditions:
        out["conditions"] = conditions
    return out


def combo(name, description, effects, after=None, before=None):
    out = {
        "name": name,
        "description": description,
        "effects": effects,
    }
    if after:
        out["after"] = after
    if before:
        out["before"] = before
    return out


def module(
    id,
    name,
    category,
    rarity,
    description,
    parameters,
    tags,
    badge="",
    min_location_tier=0,
    unlock_achievement="",
    min_victories=0,
    min_hard_victories=0,
    draft_weight=None,
    slot_effects=None,
    folded_effects=None,
    finalizing_effects=None,
    completion_effects=None,
    combos=None,
):
    if draft_weight is None:
        draft_weight = {
            "common": 1.0,
            "uncommon": 0.85,
            "rare": 0.75,
            "legendary": 0.60,
        }[rarity]
    entry = {
        "id": id,
        "name": name,
        "category": category,
        "rarity": rarity,
        "tags": tags,
        "description_template": description,
        "badge": badge,
        "parameters": parameters,
        "draft_weight": draft_weight,
        "min_location_tier": min_location_tier,
    }
    if unlock_achievement:
        entry["unlock_achievement"] = unlock_achievement
    if min_victories:
        entry["min_victories"] = min_victories
    if min_hard_victories:
        entry["min_hard_victories"] = min_hard_victories
    if slot_effects:
        entry["slot_effects"] = slot_effects
    if folded_effects:
        entry["folded_effects"] = folded_effects
    if finalizing_effects:
        entry["finalizing_effects"] = finalizing_effects
    if completion_effects:
        entry["completion_effects"] = completion_effects
    if combos:
        entry["combos"] = combos
    return entry


def build_modules():
    return [
        # 62 System Prompt
        module(
            "op.system_prompt", "System Prompt", "prompt", "uncommon",
            "+{quality} quality and the stage below runs ×{next}. First stage: another +{first_quality} quality.",
            {"quality": 8, "next": 1.25, "first_quality": 8, "combo_next": 1.15},
            ["prompt", "quality", "positional"], "SYS",
            slot_effects=[
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.next_multiplier", "$next"),
                effect("add", "stage.quality", "$first_quality", [cond("$is_first_stage", "==", True)]),
            ],
            combos=[combo(
                "Stacked Instructions",
                "After a Hand-Written Prompt the next stage gets another ×{combo_next}.",
                [effect("multiply", "stage.next_multiplier", "$combo_next")],
                after=["op.prompt"],
            )],
        ),
        # 63 Few-Shot Examples
        module(
            "op.few_shot_examples", "Few-Shot Examples", "prompt", "common",
            "+{quality} quality and the stage below runs ×{next}.",
            {"quality": 6, "next": 1.15, "combo_quality": 8},
            ["prompt", "quality", "positional"], "+{quality} Q",
            slot_effects=[
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.next_multiplier", "$next"),
            ],
            combos=[combo(
                "Something to Imitate",
                "Above a Cheap Model or Small Specialist: +{combo_quality} quality.",
                [effect("add", "stage.quality", "$combo_quality")],
                before=["op.cheap_model", "op.small_specialist"],
            )],
        ),
        # 64 Repo Map
        module(
            "op.repo_map", "Repo Map", "context", "common",
            "+{quality} quality. With {long}+ stages the next one runs ×{next}.",
            {"quality": 5, "long": 4, "next": 1.25},
            ["context", "quality", "positional"], "MAP",
            unlock_achievement="ach.repo_cartographer",
            slot_effects=[
                effect("add", "stage.quality", "$quality"),
                effect(
                    "multiply", "stage.next_multiplier", "$next",
                    [cond("$stage_count", ">=", "$long")],
                ),
            ],
        ),
        # 65 Vector Index
        module(
            "op.vector_index", "Vector Index", "context", "uncommon",
            "+{quality} quality. The stage below costs ×{cost_mult}.",
            {"quality": 10, "cost_mult": 0.75, "combo_quality": 8},
            ["context", "quality", "economy", "positional"], "VEC",
            min_location_tier=1, unlock_achievement="ach.vector_search",
            slot_effects=[
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.next_cost_mult", "$cost_mult"),
            ],
            combos=[combo(
                "Indexed Context",
                "After Large Context: another +{combo_quality} quality.",
                [effect("add", "stage.quality", "$combo_quality")],
                after=["op.large_context"],
            )],
        ),
        # 66 Context Pruner
        module(
            "op.context_pruner", "Context Pruner", "context", "uncommon",
            "×{progress} OUTPUT, ×{quality} QUALITY, ×{thermal} THERMAL.",
            {"progress": 1.25, "quality": 0.9, "thermal": 1.25},
            ["context", "output", "heat"], "×{progress}",
            min_location_tier=1,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("multiply", "stage.quality_mult", "$quality"),
                effect("multiply", "stage.thermal_mult", "$thermal"),
            ],
        ),
        # 67 Requirements Doc
        module(
            "op.requirements_doc", "Requirements Doc", "prompt", "rare",
            "First stage: +{first_quality} quality and next ×{first_next}. Otherwise +{quality} quality.",
            {"first_quality": 15, "first_next": 1.35, "quality": 5},
            ["prompt", "quality", "positional"], "REQ",
            min_location_tier=1, min_victories=1,
            slot_effects=[
                effect("add", "stage.quality", "$first_quality", [cond("$is_first_stage", "==", True)]),
                effect(
                    "multiply", "stage.next_multiplier", "$first_next",
                    [cond("$is_first_stage", "==", True)],
                ),
                effect("add", "stage.quality", "$quality", [cond("$is_first_stage", "==", False)]),
            ],
        ),
        # 68 Dependency Graph
        module(
            "op.dependency_graph", "Dependency Graph", "context", "rare",
            "Middle of the pipeline: the stage below runs ×{next}.",
            {"next": 1.5},
            ["context", "positional", "scaling"], "DEP",
            min_location_tier=1, unlock_achievement="ach.dependency_spaghetti",
            slot_effects=[
                effect(
                    "multiply", "stage.next_multiplier", "$next",
                    [
                        cond("$is_first_stage", "==", False),
                        cond("$is_last_stage", "==", False),
                    ],
                ),
            ],
        ),
        # 69 Prompt Mutator
        module(
            "op.prompt_mutator", "Prompt Mutator", "prompt", "rare",
            "OUTPUT rerolls ×0.8 / ×1.0 / ×1.5 / ×2.0. +{hidden} hidden bug.",
            {"hidden": 1},
            ["prompt", "output", "risk", "bugs"], "×?",
            min_location_tier=2, unlock_achievement="ach.chaos_prompting",
            slot_effects=[
                {
                    "operation": "reroll",
                    "target": "stage.progress_mult",
                    "value": {"pick": [0.8, 1.0, 1.5, 2.0]},
                },
                effect("add", "stage.hidden_bugs", "$hidden"),
            ],
        ),
        # 70 Constraint Solver
        module(
            "op.constraint_solver", "Constraint Solver", "prompt", "rare",
            "×{progress} OUTPUT, ×{quality} QUALITY. A clean burn: ×{clean} final OUTPUT.",
            {"progress": 0.9, "quality": 1.25, "clean": 1.15},
            ["prompt", "quality", "safe"], "SOLVE",
            min_location_tier=2, min_victories=2,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("multiply", "stage.quality_mult", "$quality"),
            ],
            finalizing_effects=[
                effect(
                    "multiply", "batch.progress_mult", "$clean",
                    [cond("batch.total_bugs_created", "==", 0)],
                ),
            ],
        ),
        # 71 Memory Palace
        module(
            "op.memory_palace", "Memory Palace", "context", "legendary",
            "{long}+ stages: ×{long_quality} QUALITY and next ×{long_next}. Otherwise ×{short_quality} QUALITY.",
            {"long": 6, "long_quality": 1.6, "long_next": 1.5, "short_quality": 1.15},
            ["context", "quality", "scaling", "positional"], "PALACE",
            min_location_tier=3, min_victories=3,
            slot_effects=[
                effect(
                    "multiply", "stage.quality_mult", "$long_quality",
                    [cond("$stage_count", ">=", "$long")],
                ),
                effect(
                    "multiply", "stage.next_multiplier", "$long_next",
                    [cond("$stage_count", ">=", "$long")],
                ),
                effect(
                    "multiply", "stage.quality_mult", "$short_quality",
                    [cond("$stage_count", "<", "$long")],
                ),
            ],
        ),
        # 72 Small Specialist
        module(
            "op.small_specialist", "Small Specialist", "model", "common",
            "×{progress} OUTPUT and +{quality} quality.",
            {"progress": 1.3, "quality": 6, "combo_quality": 6},
            ["model", "output", "quality"], "×{progress}",
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.quality", "$quality"),
            ],
            combos=[combo(
                "Briefed",
                "After a prompt or context card: +{combo_quality} quality.",
                [effect("add", "stage.quality", "$combo_quality")],
                after=[
                    "op.prompt", "op.system_prompt", "op.few_shot_examples",
                    "op.repo_map", "op.vector_index", "op.large_context",
                    "op.requirements_doc", "op.dependency_graph", "op.memory_palace",
                    "op.context_pruner", "op.prompt_mutator", "op.constraint_solver",
                ],
            )],
        ),
        # 73 MoE Router
        module(
            "op.moe_router", "MoE Router", "model", "uncommon",
            "×{progress} OUTPUT. Placed before a model, that model gets ×{combo}.",
            {"progress": 1.2, "combo": 1.25},
            ["model", "output", "positional"], "MoE",
            min_location_tier=1, unlock_achievement="ach.mixture_of_everything",
            slot_effects=[effect("multiply", "stage.progress_mult", "$progress")],
            combos=[combo(
                "Routed Expert",
                "Before a model family card: that stage gets ×{combo} OUTPUT.",
                [effect("multiply", "stage.next_multiplier", "$combo")],
                before=[
                    "op.cheap_model", "op.premium_model", "op.foundation_model",
                    "op.small_specialist", "op.draft_model", "op.judge_model",
                    "op.sparse_expert", "op.speculative_router", "op.verifier_model",
                    "op.distilled_specialist", "op.world_model", "op.self_consistency",
                ],
            )],
        ),
        # 74 Draft Model
        module(
            "op.draft_model", "Draft Model", "model", "uncommon",
            "×{progress} OUTPUT and +{bugs} bug.",
            {"progress": 1.5, "bugs": 1, "combo_next": 1.2},
            ["model", "output", "risk", "bugs"], "×{progress}",
            min_location_tier=1,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.bugs", "$bugs"),
            ],
            combos=[combo(
                "Draft and Verify",
                "Before a premium, foundation, or world model: that stage gets ×{combo_next}.",
                [effect("multiply", "stage.next_multiplier", "$combo_next")],
                before=["op.premium_model", "op.foundation_model", "op.world_model"],
            )],
        ),
        # 75 Judge Model
        module(
            "op.judge_model", "Judge Model", "model", "rare",
            "×{progress} OUTPUT, +{quality} quality, reveal {reveal} and fix {fix}.",
            {"progress": 0.85, "quality": 20, "reveal": 1, "fix": 1},
            ["model", "quality", "test", "bugs"], "JUDGE",
            min_location_tier=1, unlock_achievement="ach.spotless",
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.quality", "$quality"),
                effect("add", "stage.reveal_bugs", "$reveal"),
                effect("add", "stage.fix_bugs", "$fix"),
            ],
        ),
        # 76 Self-Consistency
        module(
            "op.self_consistency", "Self-Consistency", "model", "rare",
            "Repeats the stage above at {repeat_pct}% strength. +{quality} quality, +{heat} heat, ${cost}.",
            {"repeat": 0.6, "repeat_pct": 60, "quality": 10, "heat": 4, "cost": 100},
            ["model", "quality", "recursion", "heat", "expensive"], "CONS",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                effect("set", "stage.repeat_previous", "$repeat"),
                effect("set", "stage.repeat_count", 1),
                effect("add", "stage.quality", "$quality"),
                effect("add", "stage.heat", "$heat"),
                effect("add", "stage.cost", "$cost"),
            ],
        ),
        # 77 Sparse Expert
        module(
            "op.sparse_expert", "Sparse Expert", "model", "uncommon",
            "×{progress} OUTPUT, ×{thermal} THERMAL, ×{quality} QUALITY.",
            {"progress": 1.45, "thermal": 1.2, "quality": 0.9},
            ["model", "output", "heat"], "×{progress}",
            min_location_tier=1, unlock_achievement="ach.sparse_operator",
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("multiply", "stage.thermal_mult", "$thermal"),
                effect("multiply", "stage.quality_mult", "$quality"),
            ],
        ),
        # 78 Speculative Router
        module(
            "op.speculative_router", "Speculative Router", "model", "rare",
            "OUTPUT rerolls ×0.7 / ×1.4 / ×1.4 / ×1.8. +{heat} heat.",
            {"heat": 6},
            ["model", "output", "heat", "risk"], "×?",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                {
                    "operation": "reroll",
                    "target": "stage.progress_mult",
                    "value": {"pick": [0.7, 1.4, 1.4, 1.8]},
                },
                effect("add", "stage.heat", "$heat"),
            ],
        ),
        # 79 Verifier Model
        module(
            "op.verifier_model", "Verifier Model", "model", "rare",
            "+{quality} quality, reveal {reveal} and fix {fix}. If this stage catches anything, next ×{next}.",
            {"quality": 14, "reveal": 1, "fix": 1, "next": 1.3},
            ["model", "test", "quality", "positional"], "VERIFY",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                effect("add", "stage.quality", "$quality"),
                effect("add", "stage.reveal_bugs", "$reveal"),
                effect("add", "stage.fix_bugs", "$fix"),
            ],
            folded_effects=[
                effect(
                    "multiply", "stage.next_multiplier", "$next",
                    [cond("$stage_caught", ">", 0)],
                ),
            ],
        ),
        # 80 Distilled Specialist
        module(
            "op.distilled_specialist", "Distilled Specialist", "model", "rare",
            "×{progress} OUTPUT and +{hidden} hidden bug. After Distilled Model: no hidden bug.",
            {"progress": 1.8, "hidden": 1, "combo_hidden": -1},
            ["model", "output", "risk", "bugs"], "×{progress}",
            min_location_tier=3, min_victories=2,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.hidden_bugs", "$hidden"),
            ],
            combos=[combo(
                "Distilled Twice",
                "After Distilled Model the hidden bug cancels out.",
                [effect("add", "stage.hidden_bugs", "$combo_hidden")],
                after=["op.distillation"],
            )],
        ),
        # 81 World Model
        module(
            "op.world_model", "World Model", "model", "legendary",
            "Under {long} stages: ×{short_progress} OUTPUT, +{short_quality} quality. At {long}+: ×{long_progress} OUTPUT, +{long_quality} quality. +{heat} heat, ${cost}.",
            {
                "long": 6, "short_progress": 1.5, "short_quality": 15,
                "long_progress": 2.3, "long_quality": 25, "heat": 18, "cost": 500,
            },
            ["model", "output", "quality", "scaling", "heat", "expensive"], "WORLD",
            min_location_tier=4, min_victories=3,
            slot_effects=[
                effect(
                    "multiply", "stage.progress_mult", "$short_progress",
                    [cond("$stage_count", "<", "$long")],
                ),
                effect(
                    "add", "stage.quality", "$short_quality",
                    [cond("$stage_count", "<", "$long")],
                ),
                effect(
                    "multiply", "stage.progress_mult", "$long_progress",
                    [cond("$stage_count", ">=", "$long")],
                ),
                effect(
                    "add", "stage.quality", "$long_quality",
                    [cond("$stage_count", ">=", "$long")],
                ),
                effect("add", "stage.heat", "$heat"),
                effect("add", "stage.cost", "$cost"),
            ],
        ),
        # 82 Static Analysis
        module(
            "op.static_analysis", "Static Analysis", "test", "common",
            "Reveal {reveal}, +{quality} quality, ×{progress} OUTPUT.",
            {"reveal": 1, "quality": 5, "progress": 0.95},
            ["test", "bugs", "quality"], "STATIC",
            slot_effects=[
                effect("add", "stage.reveal_bugs", "$reveal"),
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.progress_mult", "$progress"),
            ],
        ),
        # 83 Integration Tests
        module(
            "op.integration_tests", "Integration Tests", "test", "uncommon",
            "Reveal {reveal}, fix {fix}, +{quality} quality, ×{progress} OUTPUT.",
            {"reveal": 2, "fix": 2, "quality": 10, "progress": 0.8},
            ["test", "bugs", "quality"], "INT",
            min_location_tier=1, unlock_achievement="ach.integration_day",
            slot_effects=[
                effect("add", "stage.reveal_bugs", "$reveal"),
                effect("add", "stage.fix_bugs", "$fix"),
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.progress_mult", "$progress"),
            ],
        ),
        # 84 Property Tests
        module(
            "op.property_tests", "Property Tests", "test", "uncommon",
            "Fix {fix}, +{quality} quality. Any fix: ×{final_quality} final QUALITY.",
            {"fix": 1, "quality": 8, "final_quality": 1.15},
            ["test", "bugs", "quality"], "PROP",
            min_location_tier=1, unlock_achievement="ach.property_owner",
            slot_effects=[
                effect("add", "stage.fix_bugs", "$fix"),
                effect("add", "stage.quality", "$quality"),
            ],
            folded_effects=[
                effect(
                    "multiply", "batch.quality_mult", "$final_quality",
                    [cond("$stage_fixed", ">", 0)],
                ),
            ],
        ),
        # 85 Fuzz Tester
        module(
            "op.fuzz_tester", "Fuzz Tester", "test", "uncommon",
            "Reveal {reveal}, +{bugs} bug, +{quality} quality.",
            {"reveal": 3, "bugs": 1, "quality": 5},
            ["test", "bugs", "risk"], "FUZZ",
            min_location_tier=1, unlock_achievement="ach.fuzzed_prod",
            slot_effects=[
                effect("add", "stage.reveal_bugs", "$reveal"),
                effect("add", "stage.bugs", "$bugs"),
                effect("add", "stage.quality", "$quality"),
            ],
        ),
        # 86 Mutation Testing
        module(
            "op.mutation_testing", "Mutation Testing", "test", "rare",
            "+{bugs} bugs, fix up to {fix}. {need}+ fixes this stage: ×{final_quality} final QUALITY. Still dirty.",
            {"bugs": 2, "fix": 3, "need": 2, "final_quality": 1.5},
            ["test", "bugs", "quality", "risk"], "MUT",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                effect("add", "stage.bugs", "$bugs"),
                effect("add", "stage.fix_bugs", "$fix"),
            ],
            folded_effects=[
                effect(
                    "multiply", "batch.quality_mult", "$final_quality",
                    [
                        cond("$stage_known_bugs_created", ">=", "$need"),
                        cond("$stage_fixed", ">=", "$need"),
                    ],
                ),
            ],
        ),
        # 87 Golden Dataset
        module(
            "op.golden_dataset", "Golden Dataset", "test", "rare",
            "+{quality} quality. Clean burn: ×{clean} final QUALITY.",
            {"quality": 12, "clean": 1.3},
            ["test", "quality", "safe"], "GOLD",
            min_location_tier=1, unlock_achievement="ach.golden_reference",
            slot_effects=[effect("add", "stage.quality", "$quality")],
            finalizing_effects=[
                effect(
                    "multiply", "batch.quality_mult", "$clean",
                    [cond("batch.total_bugs_created", "==", 0)],
                ),
            ],
        ),
        # 88 Canary Test
        module(
            "op.canary_test", "Canary Test", "test", "rare",
            "+{quality} quality. Next stage ×{progress} OUTPUT and creates no hidden bugs.",
            {"quality": 6, "progress": 0.95},
            ["test", "quality", "safe", "positional"], "CANARY",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.next_multiplier", "$progress"),
                effect("add", "stage.next_block_hidden", 1),
            ],
        ),
        # 89 Formal Verification
        module(
            "op.formal_verification", "Formal Verification", "test", "legendary",
            "Reveal and fix everything. ×{quality} QUALITY, ×{progress} OUTPUT, ${cost}.",
            {"reveal": 999, "fix": 999, "fix_hidden": 999, "quality": 2.0, "progress": 0.45, "cost": 1000},
            ["test", "quality", "bugs", "safe", "expensive"], "PROOF",
            min_location_tier=4, min_victories=5,
            slot_effects=[
                effect("add", "stage.reveal_bugs", "$reveal"),
                effect("add", "stage.fix_bugs", "$fix"),
                effect("add", "stage.fix_hidden_bugs", "$fix_hidden"),
                effect("multiply", "stage.quality_mult", "$quality"),
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.cost", "$cost"),
            ],
        ),
        # 90 Snapshot Tests
        module(
            "op.snapshot_tests", "Snapshot Tests", "test", "common",
            "+{quality} quality. Last stage: +{last_quality} quality instead.",
            {"quality": 5, "last_quality": 15},
            ["test", "quality", "positional"], "SNAP",
            slot_effects=[
                effect("add", "stage.quality", "$quality", [cond("$is_last_stage", "==", False)]),
                effect("add", "stage.quality", "$last_quality", [cond("$is_last_stage", "==", True)]),
            ],
        ),
        # 91 Root Cause Analysis
        module(
            "op.root_cause_analysis", "Root Cause Analysis", "test", "rare",
            "Fix {fix}. Any fix: ×{quality} QUALITY and ×{thermal} THERMAL.",
            {"fix": 2, "quality": 1.25, "thermal": 1.15},
            ["test", "bugs", "quality", "heat"], "RCA",
            min_location_tier=2, min_victories=2,
            slot_effects=[effect("add", "stage.fix_bugs", "$fix")],
            folded_effects=[
                effect(
                    "multiply", "batch.quality_mult", "$quality",
                    [cond("$stage_fixed", ">", 0)],
                ),
                effect(
                    "multiply", "batch.thermal_mult", "$thermal",
                    [cond("$stage_fixed", ">", 0)],
                ),
            ],
        ),
        # 92 Kernel Fusion
        module(
            "op.kernel_fusion", "Kernel Fusion", "hardware", "uncommon",
            "×{progress} OUTPUT and +{heat} heat.",
            {"progress": 1.4, "heat": 10},
            ["hardware", "output", "heat", "local"], "×{progress}",
            min_location_tier=1,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.heat", "$heat"),
            ],
        ),
        # 93 CUDA Graph
        module(
            "op.cuda_graph", "CUDA Graph", "hardware", "rare",
            "{long}+ stages: ×{long_progress} OUTPUT and +{heat} heat. Otherwise ×{short}.",
            {"long": 5, "long_progress": 1.6, "heat": 6, "short": 0.9},
            ["hardware", "output", "heat", "scaling", "local"], "CUDA",
            min_location_tier=2, unlock_achievement="ach.graph_capture",
            slot_effects=[
                effect(
                    "multiply", "stage.progress_mult", "$long_progress",
                    [cond("$stage_count", ">=", "$long")],
                ),
                effect("add", "stage.heat", "$heat", [cond("$stage_count", ">=", "$long")]),
                effect(
                    "multiply", "stage.progress_mult", "$short",
                    [cond("$stage_count", "<", "$long")],
                ),
            ],
        ),
        # 94 Pinned Memory
        module(
            "op.pinned_memory", "Pinned Memory", "hardware", "uncommon",
            "×{progress} OUTPUT, next cost ×{cost_mult}, +{heat} heat.",
            {"progress": 1.15, "cost_mult": 0.8, "heat": 3},
            ["hardware", "output", "economy", "heat", "local"], "PIN",
            min_location_tier=1, unlock_achievement="ach.pinned_down",
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("multiply", "stage.next_cost_mult", "$cost_mult"),
                effect("add", "stage.heat", "$heat"),
            ],
        ),
        # 95 HBM Burst
        module(
            "op.hbm_burst", "HBM Burst", "hardware", "rare",
            "×{progress} OUTPUT and +{heat} heat. Below {cold_pct}% heat: ×{thermal} THERMAL.",
            {"progress": 1.8, "heat": 20, "cold": 0.5, "cold_pct": 50, "thermal": 1.4},
            ["hardware", "output", "heat", "cooling", "local"], "HBM",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.heat", "$heat"),
                effect(
                    "multiply", "stage.thermal_mult", "$thermal",
                    [cond("$heat_ratio", "<", "$cold")],
                ),
            ],
        ),
        # 96 Fan Wall
        module(
            "op.fan_wall", "Fan Wall", "hardware", "common",
            "−{cool} heat, ×{progress} OUTPUT.",
            {"cool": -12, "progress": 0.95},
            ["hardware", "cooling", "heat", "local"], "FAN",
            slot_effects=[
                effect("add", "stage.heat", "$cool"),
                effect("multiply", "stage.progress_mult", "$progress"),
            ],
        ),
        # 97 Heat Pipe
        module(
            "op.heat_pipe", "Heat Pipe", "hardware", "common",
            "×{thermal} THERMAL, ${cost} a batch.",
            {"thermal": 1.35, "cost": 8},
            ["hardware", "cooling", "economy", "local"], "PIPE",
            min_location_tier=1, unlock_achievement="ach.cold_operator",
            slot_effects=[
                effect("multiply", "stage.thermal_mult", "$thermal"),
                effect("add", "stage.cost", "$cost"),
            ],
        ),
        # 98 Phase Change Cooling
        module(
            "op.phase_change", "Phase Change Cooling", "hardware", "legendary",
            "−{cool} heat, ×{thermal} THERMAL, ×{progress} OUTPUT, ${cost}.",
            {"cool": -30, "thermal": 2.0, "progress": 0.75, "cost": 150},
            ["hardware", "cooling", "heat", "expensive", "local"], "PHASE",
            min_location_tier=3, min_victories=3,
            slot_effects=[
                effect("add", "stage.heat", "$cool"),
                effect("multiply", "stage.thermal_mult", "$thermal"),
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.cost", "$cost"),
            ],
        ),
        # 99 Emergency Throttle
        module(
            "op.thermal_throttle", "Emergency Throttle", "hardware", "uncommon",
            "Below {threshold_pct}% heat: ×{cool_progress} OUTPUT. At or above: ×{hot_progress} OUTPUT and ×{thermal} THERMAL.",
            {
                "threshold": 0.8, "threshold_pct": 80, "cool_progress": 1.15,
                "hot_progress": 0.65, "thermal": 4.0,
            },
            ["hardware", "heat", "output", "local"], "THROT",
            min_location_tier=1, unlock_achievement="ach.thermal_event",
            slot_effects=[
                effect(
                    "multiply", "stage.progress_mult", "$cool_progress",
                    [cond("$heat_ratio", "<", "$threshold")],
                ),
                effect(
                    "multiply", "stage.progress_mult", "$hot_progress",
                    [cond("$heat_ratio", ">=", "$threshold")],
                ),
                effect(
                    "multiply", "stage.thermal_mult", "$thermal",
                    [cond("$heat_ratio", ">=", "$threshold")],
                ),
            ],
        ),
        # 100 Voltage Spike
        module(
            "op.voltage_spike", "Voltage Spike", "hardware", "rare",
            "×{progress} OUTPUT, +{heat} heat, +{hidden} hidden bug.",
            {"progress": 2.2, "heat": 30, "hidden": 1},
            ["hardware", "output", "heat", "risk", "bugs", "local"], "×{progress}",
            min_location_tier=3, min_victories=2,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.heat", "$heat"),
                effect("add", "stage.hidden_bugs", "$hidden"),
            ],
        ),
        # 101 Cold Boot
        module(
            "op.cold_boot", "Cold Boot", "hardware", "rare",
            "At or below {cold_pct}% heat: ×{cold_progress} OUTPUT and +{quality} quality. Otherwise ×{hot_progress} OUTPUT.",
            {
                "cold": 0.25, "cold_pct": 25, "cold_progress": 1.8,
                "quality": 12, "hot_progress": 0.75,
            },
            ["hardware", "output", "quality", "cooling", "local"], "COLD",
            min_location_tier=2, min_victories=2,
            slot_effects=[
                effect(
                    "multiply", "stage.progress_mult", "$cold_progress",
                    [cond("$heat_ratio", "<=", "$cold")],
                ),
                effect("add", "stage.quality", "$quality", [cond("$heat_ratio", "<=", "$cold")]),
                effect(
                    "multiply", "stage.progress_mult", "$hot_progress",
                    [cond("$heat_ratio", ">", "$cold")],
                ),
            ],
        ),
        # 102 Planner Agent
        module(
            "op.planner_agent", "Planner Agent", "agent", "common",
            "+{quality} quality and the stage below runs ×{next}.",
            {"quality": 4, "next": 1.3},
            ["agent", "quality", "positional"], "PLAN",
            slot_effects=[
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.next_multiplier", "$next"),
            ],
        ),
        # 103 Reviewer Agent
        module(
            "op.reviewer_agent", "Reviewer Agent", "agent", "uncommon",
            "Repeats the stage above at {repeat_pct}% strength and fixes {fix}.",
            {"repeat": 0.35, "repeat_pct": 35, "fix": 1},
            ["agent", "recursion", "bugs"], "REVIEW",
            min_location_tier=1, unlock_achievement="ach.code_review",
            slot_effects=[
                effect("set", "stage.repeat_previous", "$repeat"),
                effect("set", "stage.repeat_count", 1),
                effect("add", "stage.fix_bugs", "$fix"),
            ],
        ),
        # 104 Parallel Workers
        module(
            "op.parallel_workers", "Parallel Workers", "agent", "rare",
            "Two forks of the stage above at {repeat_pct}% strength. +{heat} heat.",
            {"repeat": 0.45, "repeat_pct": 45, "forks": 2, "heat": 12},
            ["agent", "recursion", "heat", "output"], "×2",
            min_location_tier=2, unlock_achievement="ach.parallel_everything",
            slot_effects=[
                effect("set", "stage.repeat_previous", "$repeat"),
                effect("set", "stage.repeat_count", "$forks"),
                effect("add", "stage.heat", "$heat"),
            ],
        ),
        # 105 Watchdog Agent
        module(
            "op.watchdog_agent", "Watchdog Agent", "agent", "uncommon",
            "Repeats the stage above at {repeat_pct}% strength and reveals {reveal} hidden bug.",
            {"repeat": 0.25, "repeat_pct": 25, "reveal": 1},
            ["agent", "recursion", "bugs", "test"], "WATCH",
            min_location_tier=1, unlock_achievement="ach.watch_this",
            slot_effects=[
                effect("set", "stage.repeat_previous", "$repeat"),
                effect("set", "stage.repeat_count", 1),
                effect("add", "stage.reveal_bugs", "$reveal"),
            ],
        ),
        # 106 Self-Critique
        module(
            "op.self_critique", "Self-Critique", "agent", "rare",
            "Repeats the stage above at {repeat_pct}% strength. +{quality} quality, ×{progress} OUTPUT.",
            {"repeat": 0.6, "repeat_pct": 60, "quality": 12, "progress": 0.9},
            ["agent", "recursion", "quality"], "CRIT",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                effect("set", "stage.repeat_previous", "$repeat"),
                effect("set", "stage.repeat_count", 1),
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.progress_mult", "$progress"),
            ],
        ),
        # 107 Tree Search
        module(
            "op.tree_search", "Tree Search", "agent", "legendary",
            "Three forks of the stage above at {repeat_pct}% strength. +{heat} heat, ${cost}.",
            {"repeat": 0.4, "repeat_pct": 40, "forks": 3, "heat": 25, "cost": 300},
            ["agent", "recursion", "heat", "expensive", "output"], "TREE",
            min_location_tier=3, min_victories=3,
            slot_effects=[
                effect("set", "stage.repeat_previous", "$repeat"),
                effect("set", "stage.repeat_count", "$forks"),
                effect("add", "stage.heat", "$heat"),
                effect("add", "stage.cost", "$cost"),
            ],
        ),
        # 108 Backtracking Agent
        module(
            "op.backtracking_agent", "Backtracking Agent", "agent", "rare",
            "Repeats the stage above at {repeat_pct}% strength and fixes {fix}.",
            {"repeat": 0.5, "repeat_pct": 50, "fix": 1},
            ["agent", "recursion", "bugs"], "BACK",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                effect("set", "stage.repeat_previous", "$repeat"),
                effect("set", "stage.repeat_count", 1),
                effect("add", "stage.fix_bugs", "$fix"),
            ],
        ),
        # 109 Autonomous Loop
        module(
            "op.autonomous_loop", "Autonomous Loop", "agent", "legendary",
            "Repeats the stage above once at full strength. +{chance_pct}% cascade chance, ×{cascade} cascade strength, +{heat} heat, +{hidden} hidden bug.",
            {
                "repeat": 1.0, "chance": 0.25, "chance_pct": 25, "cascade": 1.25,
                "heat": 30, "hidden": 1,
            },
            ["agent", "recursion", "cascade", "heat", "risk", "bugs"], "LOOP",
            min_location_tier=4, min_hard_victories=1,
            slot_effects=[
                effect("set", "stage.repeat_previous", "$repeat"),
                effect("set", "stage.repeat_count", 1),
                effect("add", "stage.cascade_chance", "$chance"),
                effect("multiply", "stage.cascade_strength", "$cascade"),
                effect("add", "stage.heat", "$heat"),
                effect("add", "stage.hidden_bugs", "$hidden"),
            ],
        ),
        # 110 Prefix Cache
        module(
            "op.prefix_cache", "Prefix Cache", "cache", "common",
            "Next cost ×{cost_mult}, next strength ×{next}.",
            {"cost_mult": 0.7, "next": 1.1},
            ["cache", "economy", "positional"], "PREFIX",
            slot_effects=[
                effect("multiply", "stage.next_cost_mult", "$cost_mult"),
                effect("multiply", "stage.next_multiplier", "$next"),
            ],
        ),
        # 111 Semantic Cache
        module(
            "op.semantic_cache", "Semantic Cache", "cache", "uncommon",
            "+{quality} quality, ×{quality_mult} QUALITY, next cost ×{cost_mult}.",
            {"quality": 8, "quality_mult": 1.1, "cost_mult": 0.75},
            ["cache", "quality", "economy"], "SEM",
            min_location_tier=1, unlock_achievement="ach.semantic_reuse",
            slot_effects=[
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.quality_mult", "$quality_mult"),
                effect("multiply", "stage.next_cost_mult", "$cost_mult"),
            ],
        ),
        # 112 KV Cache
        module(
            "op.kv_cache", "KV Cache", "cache", "rare",
            "×{progress} OUTPUT, ×{thermal} THERMAL.",
            {"progress": 1.25, "thermal": 1.25, "combo_progress": 1.2},
            ["cache", "output", "heat", "positional"], "KV",
            min_location_tier=2, min_victories=1,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("multiply", "stage.thermal_mult", "$thermal"),
            ],
            combos=[combo(
                "Long Context Cache",
                "After Large Context: another ×{combo_progress} OUTPUT.",
                [effect("multiply", "stage.progress_mult", "$combo_progress")],
                after=["op.large_context"],
            )],
        ),
        # 113 Canary Release
        module(
            "op.canary_release", "Canary Release", "deploy", "uncommon",
            "Clean burn: ×{clean} QUALITY. Dirty: ×{dirty} OUTPUT.",
            {"clean": 1.2, "dirty": 0.85},
            ["deploy", "quality", "safe", "risk"], "CANARY",
            min_location_tier=1, unlock_achievement="ach.canary_keeper",
            finalizing_effects=[
                effect(
                    "multiply", "batch.quality_mult", "$clean",
                    [cond("batch.total_bugs_created", "==", 0)],
                ),
                effect(
                    "multiply", "batch.progress_mult", "$dirty",
                    [cond("batch.total_bugs_created", ">", 0)],
                ),
            ],
        ),
        # 114 Blue/Green Deploy
        module(
            "op.blue_green", "Blue/Green Deploy", "deploy", "rare",
            "No hidden bugs remaining: ×{bonus} OUTPUT and QUALITY. ${cost}.",
            {"bonus": 1.15, "cost": 100},
            ["deploy", "quality", "output", "safe", "expensive"], "B/G",
            min_location_tier=2, min_victories=1,
            slot_effects=[effect("add", "stage.cost", "$cost")],
            finalizing_effects=[
                effect(
                    "multiply", "batch.progress_mult", "$bonus",
                    [cond("batch.hidden_bugs", "==", 0)],
                ),
                effect(
                    "multiply", "batch.quality_mult", "$bonus",
                    [cond("batch.hidden_bugs", "==", 0)],
                ),
            ],
        ),
        # 115 Rollback Plan
        module(
            "op.rollback_plan", "Rollback Plan", "deploy", "uncommon",
            "Reveal and fix hidden bugs, +{quality} quality, ×{progress} OUTPUT.",
            {"reveal": 999, "fix_hidden": 999, "quality": 8, "progress": 0.9},
            ["deploy", "bugs", "quality", "safe"], "ROLL",
            min_location_tier=2, min_victories=2,
            slot_effects=[
                effect("add", "stage.reveal_bugs", "$reveal"),
                effect("add", "stage.fix_hidden_bugs", "$fix_hidden"),
                effect("add", "stage.quality", "$quality"),
                effect("multiply", "stage.progress_mult", "$progress"),
            ],
        ),
        # 116 Friday Deploy
        module(
            "op.friday_deploy", "Friday Deploy", "deploy", "rare",
            "Last stage: ×{last_progress} OUTPUT, +{heat} heat, +{hidden} hidden bug. Otherwise ×{progress}.",
            {"last_progress": 2.0, "heat": 15, "hidden": 1, "progress": 1.05},
            ["deploy", "output", "heat", "risk", "bugs", "positional"], "FRI",
            min_location_tier=3, min_victories=3,
            slot_effects=[
                effect(
                    "multiply", "stage.progress_mult", "$last_progress",
                    [cond("$is_last_stage", "==", True)],
                ),
                effect("add", "stage.heat", "$heat", [cond("$is_last_stage", "==", True)]),
                effect("add", "stage.hidden_bugs", "$hidden", [cond("$is_last_stage", "==", True)]),
                effect(
                    "multiply", "stage.progress_mult", "$progress",
                    [cond("$is_last_stage", "==", False)],
                ),
            ],
        ),
        # 117 Singularity Cache
        module(
            "op.singularity_cache", "Singularity Cache", "cache", "legendary",
            "First stage: ×{first} OUTPUT but next ×{next}. Otherwise ×{progress}. +{heat} heat.",
            {"first": 0.5, "next": 3.0, "progress": 1.2, "heat": 10},
            ["cache", "output", "heat", "positional", "risk"], "SING",
            min_location_tier=4, min_victories=5, draft_weight=0.5,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$first", [cond("$is_first_stage", "==", True)]),
                effect(
                    "multiply", "stage.next_multiplier", "$next",
                    [cond("$is_first_stage", "==", True)],
                ),
                effect(
                    "multiply", "stage.progress_mult", "$progress",
                    [cond("$is_first_stage", "==", False)],
                ),
                effect("add", "stage.heat", "$heat"),
            ],
        ),
        # 118 Thermodynamic Computer
        module(
            "op.thermodynamic_computer", "Thermodynamic Computer", "hardware", "legendary",
            "Below {cool_pct}% heat: ×{cool}. {cool_pct}–{mid_pct}%: ×{mid}. At/above redline: ×{hot} OUTPUT but ×{thermal} THERMAL.",
            {
                "cool": 0.5, "cool_pct": 85, "cool_threshold": 0.85,
                "mid": 2.0, "mid_pct": 100, "mid_threshold": 1.0,
                "hot": 4.0, "thermal": 0.5,
            },
            ["hardware", "output", "heat", "risk", "local"], "REDLINE",
            min_location_tier=5, min_hard_victories=1, draft_weight=0.5,
            slot_effects=[
                effect(
                    "multiply", "stage.progress_mult", "$cool",
                    [cond("$heat_ratio", "<", "$cool_threshold")],
                ),
                effect(
                    "multiply", "stage.progress_mult", "$mid",
                    [
                        cond("$heat_ratio", ">=", "$cool_threshold"),
                        cond("$heat_ratio", "<", "$mid_threshold"),
                    ],
                ),
                effect(
                    "multiply", "stage.progress_mult", "$hot",
                    [cond("$heat_ratio", ">=", "$mid_threshold")],
                ),
                effect(
                    "multiply", "stage.thermal_mult", "$thermal",
                    [cond("$heat_ratio", ">=", "$mid_threshold")],
                ),
            ],
        ),
        # 119 Proof-Carrying Code
        module(
            "op.proof_carrying_code", "Proof-Carrying Code", "test", "legendary",
            "×{progress} OUTPUT, +{quality} quality. Clean completion trains +{gain} QUALITY mastery.",
            {"progress": 0.7, "quality": 20, "gain": 0.04},
            ["test", "quality", "mastery", "safe"], "+Q MASTERY",
            min_location_tier=4, min_victories=5, draft_weight=0.5,
            slot_effects=[
                effect("multiply", "stage.progress_mult", "$progress"),
                effect("add", "stage.quality", "$quality"),
            ],
            completion_effects=[
                effect(
                    "add", "mastery.quality_gain", "$gain",
                    [cond("$clean", "==", True)],
                ),
            ],
        ),
        # 120 Benchmark Daemon
        module(
            "op.benchmark_daemon", "Benchmark Daemon", "test", "legendary",
            "×{progress} OUTPUT. One-shot trains +{gain} OUTPUT; 2× overkill trains another +{overkill_gain}.",
            {"progress": 1.2, "gain": 0.03, "overkill_gain": 0.02, "overkill": 2.0},
            ["test", "output", "mastery", "overkill"], "+OUT MASTERY",
            min_location_tier=6, min_hard_victories=3, draft_weight=0.5,
            slot_effects=[effect("multiply", "stage.progress_mult", "$progress")],
            completion_effects=[
                effect(
                    "add", "mastery.output_gain", "$gain",
                    [cond("$one_shot", "==", True)],
                ),
                effect(
                    "add", "mastery.output_gain", "$overkill_gain",
                    [
                        cond("$one_shot", "==", True),
                        cond("$overkill_ratio", ">=", "$overkill"),
                    ],
                ),
            ],
        ),
    ]


def build_achievements():
    return [
        {
            "id": "ach.repo_cartographer",
            "name": "Repo Cartographer",
            "category": "milestone",
            "icon": "wrench",
            "hidden": False,
            "description": "Five stages filled. You have drawn a map of the codebase that future-you will ignore.",
            "hint": "Fill five pipeline stages in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.board_filled", "op": ">=", "value": 5}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.repo_map"},
        },
        {
            "id": "ach.vector_search",
            "name": "Found It in Context",
            "category": "milestone",
            "icon": "brain",
            "hidden": False,
            "description": "Five contracts, zero hidden bugs shipped. Retrieval is a lifestyle now.",
            "hint": "Complete five contracts in a run without shipping a hidden bug.",
            "condition": {
                "trigger": "run_end",
                "checks": [
                    {"stat": "run.completed_jobs", "op": ">=", "value": 5},
                    {"stat": "run.hidden_bugs_shipped", "op": "==", "value": 0},
                ],
            },
            "reward": {"type": "unlock_module", "module_id": "op.vector_index"},
        },
        {
            "id": "ach.dependency_spaghetti",
            "name": "Dependency Spaghetti",
            "category": "milestone",
            "icon": "wrench",
            "hidden": False,
            "description": "A full-looking pipeline that keeps looping back on itself. Somewhere a package.json is crying.",
            "hint": "Fill six pipeline stages and trigger five stage repeats in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [
                    {"stat": "run.board_filled", "op": ">=", "value": 6},
                    {"stat": "run.stage_repeats", "op": ">=", "value": 5},
                ],
            },
            "reward": {"type": "unlock_module", "module_id": "op.dependency_graph"},
        },
        {
            "id": "ach.chaos_prompting",
            "name": "Temperature: Yes",
            "category": "disaster",
            "icon": "flame",
            "hidden": False,
            "description": "Instability crossed fifty percent. The prompt is no longer a request; it is a dare.",
            "hint": "Reach 50% instability in a run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.max_instability", "op": ">=", "value": 0.5}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.prompt_mutator"},
        },
        {
            "id": "ach.mixture_of_everything",
            "name": "Mixture of Everything",
            "category": "milestone",
            "icon": "brain",
            "hidden": False,
            "description": "Ten modules owned. The angel has stopped asking what your product does.",
            "hint": "Own ten modules in a single run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.modules_owned", "op": ">=", "value": 10}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.moe_router"},
        },
        {
            "id": "ach.sparse_operator",
            "name": "Sparse Operator",
            "category": "milestone",
            "icon": "flame",
            "hidden": False,
            "description": "Hot enough to matter, finished enough to count. Density is for people with budget.",
            "hint": "Hit 90% heat and complete three contracts in one run.",
            "condition": {
                "trigger": "run_end",
                "checks": [
                    {"stat": "run.max_heat_ratio", "op": ">=", "value": 0.9},
                    {"stat": "run.completed_jobs", "op": ">=", "value": 3},
                ],
            },
            "reward": {"type": "unlock_module", "module_id": "op.sparse_expert"},
        },
        {
            "id": "ach.integration_day",
            "name": "Works on My Machine",
            "category": "milestone",
            "icon": "bug",
            "hidden": False,
            "description": "Six contracts, zero failures. The integration environment has not been invented yet.",
            "hint": "Complete six contracts in a run without failing any.",
            "condition": {
                "trigger": "run_end",
                "checks": [
                    {"stat": "run.completed_jobs", "op": ">=", "value": 6},
                    {"stat": "run.failed_jobs", "op": "==", "value": 0},
                ],
            },
            "reward": {"type": "unlock_module", "module_id": "op.integration_tests"},
        },
        {
            "id": "ach.property_owner",
            "name": "Property Owner",
            "category": "milestone",
            "icon": "bug",
            "hidden": False,
            "description": "Three clean completions. The invariants held, which is suspicious.",
            "hint": "Finish three clean contract completions in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.clean_completions", "op": ">=", "value": 3}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.property_tests"},
        },
        {
            "id": "ach.fuzzed_prod",
            "name": "Production Was the Fuzzer",
            "category": "disaster",
            "icon": "bug",
            "hidden": False,
            "description": "Eight hidden bugs created. You did not find the edge cases. The edge cases found you.",
            "hint": "Create eight hidden bugs in a single run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.hidden_bugs_created", "op": ">=", "value": 8}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.fuzz_tester"},
        },
        {
            "id": "ach.golden_reference",
            "name": "Golden Reference",
            "category": "milestone",
            "icon": "trophy",
            "hidden": False,
            "description": "Three clean one-shots. The reference answer was you, somehow.",
            "hint": "Finish three clean one-shot completions in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.clean_one_shot_completions", "op": ">=", "value": 3}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.golden_dataset"},
        },
        {
            "id": "ach.graph_capture",
            "name": "Captured the Graph",
            "category": "milestone",
            "icon": "wrench",
            "hidden": False,
            "description": "Fifteen stage repeats. The pipeline has stopped being a pipeline and become a ritual.",
            "hint": "Trigger fifteen stage repeats in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.stage_repeats", "op": ">=", "value": 15}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.cuda_graph"},
        },
        {
            "id": "ach.pinned_down",
            "name": "Pinned Down",
            "category": "milestone",
            "icon": "wrench",
            "hidden": False,
            "description": "Three machines owned. Memory is pinned. So is your rent.",
            "hint": "Own three pieces of hardware in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.hardware_owned", "op": ">=", "value": 3}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.pinned_memory"},
        },
        {
            "id": "ach.cold_operator",
            "name": "Cold Operator",
            "category": "milestone",
            "icon": "flame",
            "hidden": False,
            "description": "Four cool completions. The fans have started writing thank-you notes.",
            "hint": "Finish four cool contract completions in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.cool_completions", "op": ">=", "value": 4}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.heat_pipe"},
        },
        {
            "id": "ach.code_review",
            "name": "Reviewed Until It Hurt",
            "category": "milestone",
            "icon": "bug",
            "hidden": False,
            "description": "Ten bugs fixed. The review comments have started reviewing you.",
            "hint": "Fix ten bugs in a single run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.bugs_fixed", "op": ">=", "value": 10}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.reviewer_agent"},
        },
        {
            "id": "ach.parallel_everything",
            "name": "Parallel Everything",
            "category": "milestone",
            "icon": "wrench",
            "hidden": False,
            "description": "Twenty-five repeats and at least one cascade. The org chart has become a DAG.",
            "hint": "Trigger twenty-five stage repeats and at least one cascade in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [
                    {"stat": "run.stage_repeats", "op": ">=", "value": 25},
                    {"stat": "run.cascades_triggered", "op": ">=", "value": 1},
                ],
            },
            "reward": {"type": "unlock_module", "module_id": "op.parallel_workers"},
        },
        {
            "id": "ach.watch_this",
            "name": "Nothing Gets Past Me",
            "category": "milestone",
            "icon": "bug",
            "hidden": False,
            "description": "Ten hidden bugs revealed. The watchdog has started watching the watchdog.",
            "hint": "Reveal ten hidden bugs in a single run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.hidden_bugs_revealed", "op": ">=", "value": 10}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.watchdog_agent"},
        },
        {
            "id": "ach.semantic_reuse",
            "name": "Seen This Before",
            "category": "milestone",
            "icon": "brain",
            "hidden": False,
            "description": "Five one-shots. The cache hit rate is now a personality trait.",
            "hint": "Finish five one-shot completions in one run.",
            "condition": {
                "trigger": "tick",
                "checks": [{"stat": "run.one_shot_completions", "op": ">=", "value": 5}],
            },
            "reward": {"type": "unlock_module", "module_id": "op.semantic_cache"},
        },
        {
            "id": "ach.canary_keeper",
            "name": "Canary Still Singing",
            "category": "milestone",
            "icon": "bug",
            "hidden": False,
            "description": "Six clean completions, no hidden bugs shipped. The canary is suspiciously cheerful.",
            "hint": "Finish six clean completions in a run without shipping a hidden bug.",
            "condition": {
                "trigger": "run_end",
                "checks": [
                    {"stat": "run.clean_completions", "op": ">=", "value": 6},
                    {"stat": "run.hidden_bugs_shipped", "op": "==", "value": 0},
                ],
            },
            "reward": {"type": "unlock_module", "module_id": "op.canary_release"},
        },
    ]


def main():
    modules_path = ROOT / "content" / "modules" / "modules.json"
    achievements_path = ROOT / "content" / "achievements" / "achievements.json"

    modules = json.loads(modules_path.read_text(encoding="utf-8"))
    existing_ids = {m["id"] for m in modules}
    expansion = build_modules()
    for entry in expansion:
        if entry["id"] in existing_ids:
            raise SystemExit(f"duplicate module id: {entry['id']}")
        modules.append(entry)
        existing_ids.add(entry["id"])
    if len(modules) != 120:
        raise SystemExit(f"expected 120 modules, got {len(modules)}")
    modules_path.write_text(json.dumps(modules, indent=2) + "\n", encoding="utf-8")

    achievements = json.loads(achievements_path.read_text(encoding="utf-8"))
    by_id = {a["id"]: a for a in achievements}
    by_id["ach.spotless"]["reward"] = {
        "type": "unlock_module",
        "module_id": "op.judge_model",
    }
    by_id["ach.thermal_event"]["reward"] = {
        "type": "unlock_module",
        "module_id": "op.thermal_throttle",
    }
    for entry in build_achievements():
        if entry["id"] in by_id:
            raise SystemExit(f"duplicate achievement id: {entry['id']}")
        achievements.append(entry)
        by_id[entry["id"]] = entry
    achievements_path.write_text(
        json.dumps(achievements, indent=2) + "\n", encoding="utf-8"
    )
    print(f"modules={len(modules)} achievements={len(achievements)}")


if __name__ == "__main__":
    main()
