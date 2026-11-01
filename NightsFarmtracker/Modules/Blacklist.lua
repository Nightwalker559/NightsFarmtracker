------------------------------------------------------------------------
-- Night's Farmtracker - Blacklist
-- Items and categories dropped here are never tracked at all. Account-wide
-- and persistent; it wins over the Vendor-Only Filter and everything else.
-- One tab of the Filter window (Modules/FilterWindow.lua), built by
-- ns.CreateDropListPane.
------------------------------------------------------------------------
local _, ns = ...

ns.RegisterFilterTab({
    key = "blacklist", titleKey = "filter_tab_blacklist", enabledKey = "blacklistEnabled",
    itemsKey = "blacklist", categoriesKey = "blacklistCategories",
    categoriesTitleKey = "blacklist_categories_title", emptyKey = "blacklist_list_empty",
    clearPopup = "NFT_CONFIRM_CLEAR_ALL_BLACKLIST", clearConfirmKey = "blacklist_clear_all_confirm",
    removeGroupPopup = "NFT_CONFIRM_REMOVE_BLACKLIST_GROUP", removeGroupKey = "blacklist_remove_group_confirm",
    categoriesCollapsedKey = "blacklistCategoriesCollapsed", groupsCollapsedKey = "blacklistItemGroupsCollapsed",
    isCategoryEnabled = ns.IsBlacklistCategoryEnabled, setCategory = ns.SetBlacklistCategory,
    add = ns.AddBlacklist, remove = ns.RemoveBlacklist, clear = ns.ClearBlacklist,
})
