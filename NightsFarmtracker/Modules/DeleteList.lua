------------------------------------------------------------------------
-- Night's Farmtracker - Delete List
-- Items dragged in here can be neither sold nor auctioned (e.g. Warband-bound
-- potions): the Sell List at a vendor offers them for deletion, one item per
-- click (the game allows one deletion per click). Items only, no categories.
-- Account-wide and persistent. One tab of the Filter window
-- (Modules/FilterWindow.lua), built by ns.CreateDropListPane.
------------------------------------------------------------------------
local _, ns = ...

ns.RegisterFilterTab({
    key = "delete", titleKey = "filter_tab_delete", enabledKey = "deleteListEnabled",
    itemsKey = "deleteList", emptyKey = "delete_list_empty",
    clearPopup = "NFT_CONFIRM_CLEAR_ALL_DELETE", clearConfirmKey = "delete_clear_all_confirm",
    removeGroupPopup = "NFT_CONFIRM_REMOVE_DELETE_GROUP", removeGroupKey = "delete_remove_group_confirm",
    groupsCollapsedKey = "deleteItemGroupsCollapsed",
    add = ns.AddDeleteList, remove = ns.RemoveDeleteList, clear = ns.ClearDeleteList,
})
