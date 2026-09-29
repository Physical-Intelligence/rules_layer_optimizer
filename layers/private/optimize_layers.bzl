"""Optimize OCI layer groups under a final image layer budget."""

load("//layers/private:layer_groups.bzl", "LayerTarsInfo", "SizeHintInfo")

MAX_DOCKER_LAYERS = 127
_OVERFLOW_FLATTEN = "flatten"
_OVERFLOW_INDIVIDUAL = "individual"
_GROUP_NAME_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
_OPTIMIZATION_PLAN_OUTPUT_GROUP = "optimization_plan"

def optimize_layers_rule_impl(ctx):
    """Optimize ordered layer groups under a shared budget.

    Each dependency contributes tar files through `DefaultInfo`. If it also
    provides `SizeHintInfo`, those files are eligible for thresholding and
    dynamic spill-to-flat behavior. The provider intentionally carries only
    metadata; group membership and unsized-file policy come from this rule's
    attributes so apt, pip, interpreter, extras, and source can be budgeted
    together without producer-specific layer policy.

    Args:
        ctx: The rule context.

    Returns:
        A DefaultInfo provider with ordered tar files.
        An OutputGroupInfo provider with per-group tar groups consumed by the macro.
    """
    grouped = {}
    if len(ctx.attr.layer_group_deps) != len(ctx.attr.layer_group_names):
        fail("layer_group_deps and layer_group_names must have matching lengths")
    if len(ctx.attr.layer_group_order) != len(ctx.attr.layer_group_overflows):
        fail("layer_group_order and layer_group_overflows must have matching lengths")
    group_overflows = {
        ctx.attr.layer_group_order[i]: ctx.attr.layer_group_overflows[i]
        for i in range(len(ctx.attr.layer_group_order))
    }

    for i in range(len(ctx.attr.layer_group_deps)):
        dep = ctx.attr.layer_group_deps[i]
        group_name = ctx.attr.layer_group_names[i]
        files = _layer_tars(dep)
        file_sizes = dep[SizeHintInfo].sizes if SizeHintInfo in dep else {}
        file_set = {f: True for f in files}
        for f, size in file_sizes.items():
            if f not in file_set:
                fail("{} provides a size hint for {}, which is not in its layer tar files".format(dep.label, f.short_path))
            if size <= 0:
                fail("{} provides a non-positive size hint {} for {}".format(dep.label, size, f.short_path))
        _merge_group(
            grouped = grouped,
            name = group_name,
            files = files,
            file_sizes = file_sizes,
        )

    groups = _ordered_groups(grouped, ctx.attr.layer_group_order, group_overflows)
    file_groups = {}
    for group in groups:
        for f in _deduplicate(group.files):
            previous_group = file_groups.get(f)
            if previous_group != None and previous_group != group.name:
                fail("layer tar {} belongs to both '{}' and '{}'".format(f.short_path, previous_group, group.name))
            file_groups[f] = group.name
    all_files = []
    for group in groups:
        all_files.extend(group.files)

    generated_layer_limit = ctx.attr.layer_budget
    if generated_layer_limit < 1:
        fail("layer_budget must be positive, got {}".format(generated_layer_limit))
    if ctx.attr.size_bytes_threshold < 0:
        fail("size_bytes_threshold must be non-negative, got {}".format(ctx.attr.size_bytes_threshold))

    if ctx.attr.flatten_all:
        file_statuses = {f: "flatten_all" for f in all_files}
        plan_file = _write_optimization_plan(ctx, _optimization_plan(
            ctx = ctx,
            groups = groups,
            emitted_files = all_files,
            file_statuses = file_statuses,
            generated_layer_limit = generated_layer_limit,
            flatten_all = True,
        ))
        return [
            DefaultInfo(files = depset(all_files)),
            OutputGroupInfo(**{_OPTIMIZATION_PLAN_OUTPUT_GROUP: depset([plan_file])}),
        ]
    if generated_layer_limit <= 1:
        fail("optimized layer grouping requires at least 2 generated layers; got {}".format(generated_layer_limit))

    fixed_layer_counts = {}
    fixed_flat_layers = len([group for group in groups if group.overflow == _OVERFLOW_FLATTEN])
    for group in groups:
        if group.overflow == _OVERFLOW_FLATTEN:
            fixed_layer_counts[group.name + "_flat"] = 1

    fixed_individual_layers = 0
    sizable_candidates = []
    file_statuses = {}
    group_outputs = {}

    for group in groups:
        files = _deduplicate(group.files)
        file_sizes = group.file_sizes
        fixed_files = []
        flat_files = []

        if group.overflow == _OVERFLOW_INDIVIDUAL and file_sizes:
            fail("layer group '{}' uses overflow='individual' but received SizeHintInfo; use overflow='flatten' for size-budgeted candidates".format(group.name))

        for f in files:
            if group.overflow == _OVERFLOW_FLATTEN and f in file_sizes:
                size = file_sizes[f]
                if size >= ctx.attr.size_bytes_threshold:
                    sizable_candidates.append(struct(
                        group = group.name,
                        file = f,
                        size = size,
                    ))
                else:
                    file_statuses[f] = "below_size_threshold"
                    flat_files.append(f)
            elif group.overflow == _OVERFLOW_FLATTEN:
                file_statuses[f] = "missing_size_hint"
                flat_files.append(f)
            else:
                file_statuses[f] = "fixed"
                fixed_files.append(f)

        fixed_individual_layers += len(fixed_files)
        if fixed_files:
            fixed_layer_counts[group.name] = fixed_layer_counts.get(group.name, 0) + len(fixed_files)
        group_outputs[group.name] = struct(
            individual_files = fixed_files,
            flat_files = flat_files,
        )

    available_sizable_layers = generated_layer_limit - fixed_flat_layers - fixed_individual_layers
    if available_sizable_layers < 0:
        fail("fixed OCI layer groups require {} generated layers ({}), exceeding layer budget {}".format(
            fixed_flat_layers + fixed_individual_layers,
            _format_layer_counts(fixed_layer_counts),
            generated_layer_limit,
        ))

    sizable_candidates = sorted(
        sizable_candidates,
        key = lambda c: (-c.size, c.group, c.file.short_path),
    )
    kept_sizable = {candidate.file: True for candidate in sizable_candidates[:available_sizable_layers]}

    individual_candidate_files = {name: [] for name in group_outputs.keys()}
    flat_candidate_files = {name: [] for name in group_outputs.keys()}
    for candidate in sizable_candidates:
        if candidate.file in kept_sizable:
            file_statuses[candidate.file] = "above_size_threshold"
            individual_candidate_files[candidate.group].append(candidate.file)
        else:
            file_statuses[candidate.file] = "layer_budget_exceeded"
            flat_candidate_files[candidate.group].append(candidate.file)

    for group_name, output in group_outputs.items():
        group_outputs[group_name] = struct(
            individual_files = output.individual_files + individual_candidate_files[group_name],
            flat_files = output.flat_files + flat_candidate_files[group_name],
        )

    ordered_files = []
    output_groups = {}
    for group in groups:
        output = group_outputs[group.name]
        ordered_files.extend(output.individual_files)
        ordered_files.extend(output.flat_files)
        output_groups[_individual_output_group(group.name)] = depset(output.individual_files)
        if group.overflow == _OVERFLOW_FLATTEN:
            output_groups[_flat_output_group(group.name)] = depset(output.flat_files)

    plan_file = _write_optimization_plan(ctx, _optimization_plan(
        ctx = ctx,
        groups = groups,
        group_outputs = group_outputs,
        file_statuses = file_statuses,
        emitted_files = ordered_files,
        generated_layer_limit = generated_layer_limit,
        sizable_candidates = sizable_candidates,
        kept_sizable = kept_sizable,
    ))
    output_groups[_OPTIMIZATION_PLAN_OUTPUT_GROUP] = depset([plan_file])

    return [
        DefaultInfo(files = depset(ordered_files)),
        OutputGroupInfo(**output_groups),
    ]

optimize_layers_rule = rule(
    implementation = optimize_layers_rule_impl,
    attrs = {
        "layer_group_deps": attr.label_list(allow_files = True),
        "layer_group_names": attr.string_list(),
        "layer_budget": attr.int(mandatory = True),
        "size_bytes_threshold": attr.int(mandatory = True),
        "layer_group_order": attr.string_list(default = []),
        "layer_group_overflows": attr.string_list(default = []),
        "flatten_all": attr.bool(default = False),
    },
    provides = [DefaultInfo, OutputGroupInfo],
)

def optimized_layers_plan(
        name,
        groups,
        layer_budget,
        size_bytes_threshold,
        flatten_all = False,
        tags = [],
        visibility = None):
    """Plans grouped OCI layers without selecting a tar materialization backend.

    `groups` is the public grouping policy: producers contribute tar files plus
    optional `SizeHintInfo`, and this macro decides how group order, static
    thresholds, dynamic layer-budget spill, and overflow layers interact.

    Args:
        name: Prefix for the generated planning and output-group targets.
        groups: Ordered list of `layer_group(...)` structs.
        size_bytes_threshold: Minimum size in bytes for a size-hinted tar to be eligible for an individual layer.
        layer_budget: Maximum number of layers this target may generate.
        flatten_all: If true, flattens all grouped tars into one layer.
        tags: Tags to apply to generated helper targets.
        visibility: Visibility of the public plan and per-group output targets.

    Returns:
        A struct containing the all-tars target, per-group output targets, and JSON plan target.
    """
    group_inputs = _flatten_explicit_group_inputs(groups)
    all_tars = name + "_all_tars"

    optimize_layers_rule(
        name = all_tars,
        layer_group_deps = group_inputs.deps,
        layer_group_names = group_inputs.names,
        size_bytes_threshold = size_bytes_threshold,
        layer_budget = layer_budget,
        layer_group_order = group_inputs.order,
        layer_group_overflows = group_inputs.overflows,
        flatten_all = flatten_all,
        tags = tags,
        visibility = visibility,
    )

    native.filegroup(
        name = name + "_optimization_plan",
        srcs = [all_tars],
        output_group = _OPTIMIZATION_PLAN_OUTPUT_GROUP,
        tags = tags,
        visibility = visibility,
    )

    planned_groups = []
    if not flatten_all:
        for i in range(len(group_inputs.order)):
            group_name = group_inputs.order[i]
            individual_tars = _target_name(name, group_name, "individual_tars")
            native.filegroup(
                name = individual_tars,
                srcs = [all_tars],
                output_group = _individual_output_group(group_name),
                tags = tags,
                visibility = visibility,
            )
            flat_tars = None
            if group_inputs.overflows[i] == _OVERFLOW_FLATTEN:
                flat_tars = _flat_tars_name(name, group_name)
                native.filegroup(
                    name = flat_tars,
                    srcs = [all_tars],
                    output_group = _flat_output_group(group_name),
                    tags = tags,
                    visibility = visibility,
                )
            planned_groups.append(struct(
                flat_tars = flat_tars,
                individual_tars = individual_tars,
                name = group_name,
            ))

    return struct(
        all_tars = all_tars,
        flatten_all = flatten_all,
        groups = planned_groups,
        optimization_plan = name + "_optimization_plan",
    )

def _merge_group(grouped, name, files, file_sizes):
    existing = grouped.get(name, None)
    if existing:
        merged_sizes = dict(existing.file_sizes)
        for f, size in file_sizes.items():
            previous_size = merged_sizes.get(f)
            if previous_size != None and previous_size != size:
                fail("layer tar {} has conflicting size hints {} and {}".format(f.short_path, previous_size, size))
            merged_sizes[f] = size
        grouped[name] = struct(
            files = existing.files + files,
            file_sizes = merged_sizes,
        )
    else:
        grouped[name] = struct(
            files = files,
            file_sizes = dict(file_sizes),
        )

def _layer_tars(dep):
    if LayerTarsInfo in dep:
        return dep[LayerTarsInfo].tars
    if DefaultInfo in dep:
        files = dep[DefaultInfo].files.to_list()
        if len(files) > 1:
            fail("{} has multiple default outputs; provide LayerTarsInfo to select its layer tars".format(dep.label))
        return files
    return []

def _flatten_explicit_group_inputs(groups):
    if type(groups) != "list":
        fail("groups must be a list of layer_group(...) entries")

    deps = []
    names = []
    order = []
    overflows = []
    seen = {}
    for group in groups:
        if not hasattr(group, "name") or not hasattr(group, "targets"):
            fail("groups entries must come from layer_group(...)")
        name = group.name
        _validate_group_name(name)
        if type(group.targets) != "list":
            fail("layer_group '{}' targets must be a list".format(name))
        overflow = getattr(group, "overflow", _OVERFLOW_INDIVIDUAL)
        if overflow not in [_OVERFLOW_FLATTEN, _OVERFLOW_INDIVIDUAL]:
            fail("layer_group '{}' overflow must be 'flatten' or 'individual', got '{}'".format(name, overflow))
        if not group.targets:
            continue
        if name in seen:
            fail("duplicate layer group '{}'".format(name))
        seen[name] = True
        order.append(name)
        overflows.append(overflow)
        for target in group.targets:
            deps.append(target)
            names.append(name)
    return struct(
        deps = deps,
        names = names,
        order = order,
        overflows = overflows,
    )

def _ordered_groups(grouped, layer_group_order, group_overflows):
    ordered = []
    seen = {}
    for name in layer_group_order:
        if name in grouped:
            ordered.append(struct(
                name = name,
                files = grouped[name].files,
                file_sizes = grouped[name].file_sizes,
                overflow = group_overflows.get(name, _OVERFLOW_INDIVIDUAL),
            ))
            seen[name] = True

    for name in sorted([name for name in grouped.keys() if name not in seen]):
        ordered.append(struct(
            name = name,
            files = grouped[name].files,
            file_sizes = grouped[name].file_sizes,
            overflow = group_overflows.get(name, _OVERFLOW_INDIVIDUAL),
        ))

    return ordered

def _deduplicate(files):
    return {f: True for f in files}.keys()

def _format_layer_counts(layer_counts):
    entries = [
        "{}={}".format(name, layer_counts[name])
        for name in sorted(layer_counts.keys())
        if layer_counts[name]
    ]
    if not entries:
        return "none"
    return ", ".join(entries)

def _optimization_plan(
        ctx,
        groups,
        emitted_files,
        generated_layer_limit,
        flatten_all = False,
        group_outputs = {},
        file_statuses = {},
        sizable_candidates = [],
        kept_sizable = {}):
    file_sizes = _combined_file_sizes(groups)
    layers = _plan_layer_entries(
        groups = groups,
        group_outputs = group_outputs,
        file_sizes = file_sizes,
        file_statuses = file_statuses,
        flatten_all = flatten_all,
        rule_files = emitted_files,
    )
    separate_layer_count = len([layer for layer in layers if layer["disposition"] == "separate"])
    flattened_layer_count = len(layers) - separate_layer_count
    return {
        "groups": _plan_group_entries(groups, group_outputs, flatten_all),
        "layers": layers,
        "policy": {
            "flatten_all": flatten_all,
            "layer_budget": generated_layer_limit,
            "size_threshold_bytes": ctx.attr.size_bytes_threshold,
        },
        "schema_version": 1,
        "summary": {
            "flattened_layer_count": flattened_layer_count,
            "input_tar_count": len(emitted_files),
            "output_layer_count": len(layers),
            "separate_layer_count": separate_layer_count,
            "size_eligible_input_count": len(sizable_candidates),
            "size_eligible_inputs_kept_separate": len(kept_sizable),
        },
        "target": str(ctx.label),
    }

def _combined_file_sizes(groups):
    sizes = {}
    for group in groups:
        sizes.update(group.file_sizes)
    return sizes

def _plan_group_entries(groups, group_outputs, flatten_all):
    entries = []
    for group in groups:
        separate_layer_count = 0
        flattened_layer_count = 0
        if not flatten_all:
            output = group_outputs[group.name]
            separate_layer_count = len(output.individual_files)
            flattened_layer_count = 1 if group.overflow == _OVERFLOW_FLATTEN else 0
        entries.append({
            "flattened_layer_count": flattened_layer_count,
            "input_tar_count": len(_deduplicate(group.files)),
            "name": group.name,
            "output_layer_count": separate_layer_count + flattened_layer_count,
            "overflow": group.overflow,
            "separate_layer_count": separate_layer_count,
        })
    return entries

def _plan_layer_entries(groups, group_outputs, file_sizes, file_statuses, flatten_all, rule_files):
    if flatten_all:
        layer = _plan_layer_entry("all", "flattened", rule_files, file_sizes, file_statuses)
        layer["source_groups"] = [group.name for group in groups]
        return [layer]

    entries = []
    for group in groups:
        output = group_outputs[group.name]
        for f in output.individual_files:
            entries.append(_plan_layer_entry(group.name, "separate", [f], file_sizes, file_statuses))
        if group.overflow == _OVERFLOW_FLATTEN:
            entries.append(_plan_layer_entry(group.name, "flattened", output.flat_files, file_sizes, file_statuses))
    return entries

def _plan_layer_entry(group, disposition, files, file_sizes, file_statuses):
    known_input_size_bytes = 0
    for f in files:
        known_input_size_bytes += file_sizes.get(f, 0)
    return {
        "disposition": disposition,
        "group": group,
        "inputs": [_plan_input_entry(f, file_sizes, file_statuses) for f in files],
        "known_input_size_bytes": known_input_size_bytes,
        "unknown_input_count": len([f for f in files if f not in file_sizes]),
    }

def _plan_input_entry(f, file_sizes, file_statuses):
    entry = {
        "path": f.short_path,
        "reason": file_statuses.get(f, "unclassified"),
    }
    if f in file_sizes:
        entry["size_hint_bytes"] = file_sizes[f]
    return entry

def _write_optimization_plan(ctx, plan):
    plan_file = ctx.actions.declare_file(ctx.label.name + "_optimization_plan.json")
    ctx.actions.write(plan_file, json.encode_indent(plan, indent = "  ") + "\n")
    return plan_file

def _individual_output_group(group_name):
    return group_name + "_individual"

def _flat_output_group(group_name):
    return group_name + "_flat"

def _target_name(name, group_name, suffix):
    return "{}_{}_{}".format(name, group_name, suffix)

def _flat_tars_name(name, group_name):
    return _target_name(name, group_name, "flat_tars")

def _validate_group_name(group_name):
    if not group_name:
        fail("layer group names must be non-empty")
    for c in group_name.elems():
        if _GROUP_NAME_CHARS.find(c) < 0:
            fail("layer group name '{}' must use only letters, numbers, and '_'".format(group_name))
