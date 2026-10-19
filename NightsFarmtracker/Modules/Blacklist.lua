------------------------------------------------------------------------
-- Night's Farmtracker - Blacklist
-- Items and categories dropped here are never tracked at all. Account-wide
-- and persistent; it wins over the Vendor-Only Filter and everything else.
-- The window itself comes from ns.CreateDropListWindow.
------------------------------------------------------------------------
local _, ns = ...

ns.CreateDropListWindow({
    frameName = "NightsFarmtrackerBlacklistWnd", frameKey = "BlacklistFrame",
    rebuildKey = "RebuildBlacklistList", toggleKey = "ToggleBlacklistWindow",
    enabledKey = "blacklistEnabled",
    itemsKey = "blacklist", categoriesKey = "blacklistCategories",
    titleKey = "blacklist_title", categoriesTitleKey = "blacklist_categories_title", emptyKey = "blacklist_list_empty",
    clearPopup = "NFT_CONFIRM_CLEAR_ALL_BLACKLIST", clearConfirmKey = "blacklist_clear_all_confirm",
    removeGroupPopup = "NFT_CONFIRM_REMOVE_BLACKLIST_GROUP", removeGroupKey = "blacklist_remove_group_confirm",
    categoriesCollapsedKey = "blacklistCategoriesCollapsed", groupsCollapsedKey = "blacklistItemGroupsCollapsed",
    isCategoryEnabled = ns.IsBlacklistCategoryEnabled, setCategory = ns.SetBlacklistCategory,
    add = ns.AddBlacklist, remove = ns.RemoveBlacklist, clear = ns.ClearBlacklist,
})
