------------------------------------------------------------------------
-- Night's Farmtracker - Vendor-Only Filter
-- Items dragged in here are always valued at vendor price, never AH, and
-- whole categories or expansions can be switched the same way. Account-wide
-- and persistent. The window itself comes from ns.CreateDropListWindow.
------------------------------------------------------------------------
local _, ns = ...

ns.CreateDropListWindow({
    frameName = "NightsFarmtrackerFilterWnd", frameKey = "FilterFrame",
    rebuildKey = "RebuildFilterList", toggleKey = "ToggleFilterWindow",
    enabledKey = "vendorFilterEnabled",
    itemsKey = "forceVendor", categoriesKey = "forceVendorCategories",
    titleKey = "filter_title", categoriesTitleKey = "filter_categories_title", emptyKey = "filter_list_empty",
    clearPopup = "NFT_CONFIRM_CLEAR_ALL_FILTER", clearConfirmKey = "filter_clear_all_confirm",
    removeGroupPopup = "NFT_CONFIRM_REMOVE_FILTER_GROUP", removeGroupKey = "filter_remove_group_confirm",
    categoriesCollapsedKey = "filterCategoriesCollapsed", groupsCollapsedKey = "filterItemGroupsCollapsed",
    isCategoryEnabled = ns.IsForceVendorCategoryEnabled, setCategory = ns.SetForceVendorCategory,
    add = ns.AddForceVendor, remove = ns.RemoveForceVendor, clear = ns.ClearForceVendor,
    expansions = {
        titleKey = "filter_ah_expansions_title", hintKey = "filter_ah_expansions_hint",
        collapsedKey = "ahExpansionsCollapsed",
    },
})
