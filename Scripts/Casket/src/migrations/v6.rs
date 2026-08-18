// &desc: "v5 -> v6: no meta-JSON shape change, no in-place layout change -- this step exists purely to carry `requires_new_image`. Vaults created before this version were formatted with cryptsetup's/this codebase's old 16 MiB LUKS2 data offset; reaching v6 means the vault gets rebuilt with the new `config::LUKS_DATA_OFFSET_MB` (128) offset via `migrations::image_rebuild::rebuild`, reserving free space for `header::room`'s v3 flavor to live inside the offset region instead of a separate sibling file. See `image_rebuild.rs` for the actual rebuild mechanics and `commands/open.rs` for the confirm-prompt/progress UX that gates it."
use super::Step;

pub const STEP: Step = Step {
    version: 6,
    meta: None,
    layout: None,
    requires_new_image: true,
};
