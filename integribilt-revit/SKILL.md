---
name: integribilt-revit
description: IntegriBilt Revit BIM model interaction via two MCP servers (Nonica and IntegriBilt custom). Triggers for any Revit model queries, element creation/modification, family editing, view management, annotations, exports, clash detection, or worksharing tasks.
---

# IntegriBilt Revit MCP

## MCP Servers

| Server Prefix | Provider | Scope |
|---------------|----------|-------|
| `mcp__Revit__` | Nonica | 40+ tools — element queries, parameters, graphics, transforms, schedules, worksets, creation pipeline |
| `mcp__integribilt-revit__` | IntegriBilt | 30+ tools — direct creation (walls/floors/doors/rooms), family editing, annotations, exports, clashes |

## Critical Rules

- **All coordinates and dimensions are in feet** (internal Revit units)
- **Rotation angles are in radians** — positive = counterclockwise
- **`get_category_by_keyword` keyword must match Revit's `language_of_model`** — use chat language for first call
- **Parameters first, Additional Properties as fallback** — use `get_parameters_from_elementid` before `get_all_additional_properties_from_elementid`
- **Selection/isolation shortcuts** — `set_user_selection_in_revit` and `set_isolated_elements_in_view` accept type or category IDs directly (auto-selects all instances)
- **No graphics overrides on linked document elements** — do not use `get_graphic_overrides_for_element_ids_in_view` or `set_graphic_overrides_for_elements_in_view` with linked elements
- **Respect MAX per-request limits** — many Nonica tools have item count limits (see references/tools.md)
- **Family hierarchy**: Family -> Type -> Element (instance). Navigate with `get_all_used_families_of_category` -> `get_all_used_types_of_families` -> `get_all_elementids_for_specific_type_ids`

## Key Workflows

### Discover -> Query -> Modify (Nonica)
1. `get_category_by_keyword(keyword)` — get category ID
2. `get_elements_by_category(categoryId)` — get element IDs
3. `get_parameters_from_elementid(elementId)` — get parameter IDs/names (single element)
4. `get_parameter_value_for_element_ids(list_elementIds, idParameter)` — bulk read (MAX 500)
5. `set_parameter_value_for_elements(list_elementIds, idParameter, list_newValues)` — bulk write

### Creation Pipeline (Nonica)
1. `create_tool_names_explorer()` — list all available creation tools
2. `create_tool_arguments_explorer(list_toolNames)` — get arguments for specific tools
3. `create_tools_invoker(toolName, argumentIdsAndValues)` — execute creation (units in feet)

### Direct Creation (IntegriBilt)
Use `create_walls`, `create_floors`, `create_doors`, `create_levels`, `create_room`, `place_family_by_coordinate` for straightforward element creation without the pipeline.

### Family Editing (IntegriBilt)
1. `open_family_document(path)` — open .rfa file
2. Create geometry: `create_extrusion`, `create_void_extrusion`, `create_sweep`, `create_reference_plane`
3. Add parameters: `add_family_parameter`, `set_family_parameter` (supports formulas)
4. Load into project: `load_family_into_project()` or `load_family_from_path(path)`

### Linked Documents (Nonica)
- `get_document_switched(elementId)` — switch to linked document context
- `get_document_switched(switchMainDoc=true)` — switch back to main document
- All subsequent calls operate on the switched document

## Per-Request Limits (Nonica Tools)

| Limit | Tools |
|-------|-------|
| MAX 30 | `get_all_elements_of_specific_families`, `get_boundary_lines`, `get_size_in_mb_of_families` |
| MAX 50 | `get_schedules_info_and_columns`, `get_graphic_filters_applied_to_views`, `get_all_elementids_for_specific_type_ids` |
| MAX 100 | `get_material_layers_from_types`, `get_graphic_overrides_*`, `get_viewports_and_schedules_on_sheets`, `get_worksharing_information_for_element_ids`, `set_movement/rotation/copy_for_elements` |
| MAX 200 | `get_host_id_for_element_ids` |
| MAX 500 | `get_parameter_value_for_element_ids`, `get_additional_property_for_all_elementids`, `set_additional_property_for_all_elements`, `get_element_types_for_elementids`, `get_location_for_element_ids`, `get_boundingboxes_for_element_ids`, `set_parameter_value_for_elements` |
| MAX 1000 | `get_worksets_from_elementids`, `get_if_elements_pass_filter`, `get_categories_from_elementids`, `get_object_classes_from_elementids` |

## Tool Categories Summary

### Nonica (`mcp__Revit__`)
- **Element Discovery**: categories, elements by category/family/view/type
- **Parameters**: read single, bulk read/write by parameter ID
- **Additional Properties**: fallback read/write by property name
- **Types & Families**: family/type listing, type-to-element lookup
- **Geometry & Location**: location points/curves, bounding boxes, boundary lines
- **Materials**: layer composition for wall/floor/roof/ceiling types
- **View & Selection**: active view, user selection, isolation
- **Graphics Overrides**: element-level and filter-level color/pattern overrides
- **Transforms**: move, rotate, copy, delete elements
- **Schedules & Sheets**: schedule columns, viewport placement, revision assignment
- **Worksets & Worksharing**: workset assignment, creator/owner info
- **Utilities**: filter testing, object classes, host elements, warnings, project units, family file sizes
- **Creation Pipeline**: tool discovery -> argument lookup -> invocation
- **Document Switching**: linked document context management

### IntegriBilt (`mcp__integribilt-revit__`)
- **Direct Creation**: walls, floors, doors, levels, rooms, family placement
- **Queries & Editing**: find elements, modify parameters, delete elements
- **Family Editing**: open .rfa, reference planes, extrusions, voids, sweeps, parameters, formulas, load to project
- **Geometry**: element geometry extraction (bounding box, solids, faces)
- **View Management**: visibility/halftone overrides per element or category
- **Materials**: material physical and visual properties
- **Annotations**: detail lines, model lines, text notes, tags, dimensions, section views, filled regions
- **Openings**: shaft openings (multi-floor), opening cuts (single element)
- **Assembly & Export**: assembly views (shop drawings), PDF export, DWG export
- **Transforms**: mirror with optional copy
- **Worksets & Phases**: workset assignment, phase management (created/demolished)
- **Links & Clashes**: query linked document elements, intersection clash detection
