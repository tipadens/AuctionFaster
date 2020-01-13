---@type AuctionFaster
local AuctionFaster = unpack(select(2, ...));
--- @var StdUi StdUi
local StdUi = LibStub('StdUi');
local L = LibStub('AceLocale-3.0'):GetLocale('AuctionFaster');

--- @type Auctions
local Auctions = AuctionFaster:GetModule('Auctions');

--- @type Buy
local Buy = AuctionFaster:GetModule('Buy');

--- @type ChainBuy
local ChainBuy = AuctionFaster:GetModule('ChainBuy');
--- @type AuctionCache
local AuctionCache = AuctionFaster:GetModule('AuctionCache');
--- @type CommodityBuy
local CommodityBuy = AuctionFaster:GetModule('CommodityBuy');

local format = string.format;
local TableInsert = tinsert;

function Buy:Enable()
	self:AddBuyAuctionHouseTab();
	self:InterceptLinkClick();
end

function Buy:OnShow()

	self.buyTab.auctions = {};
	self.buyTab.items = {};

	self:UpdateSearchAuctions();
	self:UpdateStateText();
	--self:UpdatePager();

	self:InitTutorial();
end

function Buy:OnHide()

end

function Buy:Disable()
end

----------------------------------------------------------------------------
--- Searching functions
----------------------------------------------------------------------------

function Buy:SearchAuctions(name, exact)
	self.currentQuery = {
		name = name,
		exact = exact or false,
	};

	self:ApplyFilters(self.currentQuery);

	self:ClearSearchAuctions();
	self:UpdateStateText(true);
	self:SaveRecentSearches(name);

	Auctions:QueryAuctions(self.currentQuery, function(items)
		Buy:SearchAuctionsCallback(items)
	end);
end

function Buy:SearchItem(itemKey)
	self.currentQuery = {
		itemKey = itemKey,
	};

	self:ApplyFilters(self.currentQuery);

	self:ClearSearchAuctions();
	self:UpdateStateText(true);

	Auctions:QueryItem(self.currentQuery, function(items)
		Buy:SearchItemCallback(items)
	end);
end

function Buy:SearchFavoriteItems()
	self.currentQuery = {
		favorites = true,
	};

	self:ClearSearchAuctions();
	self:UpdateStateText(true);

	Auctions:SearchFavoriteItems(self.currentQuery, function(items)
		Buy:SearchItemCallback(items)
	end);
end

function Buy:SaveRecentSearches(searchQuery)
	local rs = AuctionFaster.db.buy.recentSearches;
	local historyLimit = 100;

	for _, v in pairs(rs) do
		if v.text:lower() == searchQuery:lower() then
			return;
		end
	end

	TableInsert(rs, 1, {value = searchQuery, text = searchQuery});
	if #rs > historyLimit then
		for i = historyLimit + 1, #rs do
			rs[i] = nil;
		end
	end
end

function Buy:RefreshSearchAuctions()
	if not self.currentQuery then
		AuctionFaster:Echo(3, L['No query was searched before']);
		return;
	end

	if self.currentQuery.itemKey then
		-- sending another query
		self:SearchItem(self.currentQuery.itemKey);
	else
		self:SearchAuctions(self.currentQuery.name, self.currentQuery.exact);
	end
end

----------------------------------------------------------------------------
--- Searching callback function
----------------------------------------------------------------------------

function Buy:SearchAuctionsCallback(items)
	print(#items)
	-- TODO: this needs to be done twice
	-- AuctionCache:ParseScanResults(items);
	self.buyTab.items = items;
	self.mode = 'items';

	self:UpdateSearchAuctions();
	self:UpdateStateText();
end

function Buy:SearchItemCallback(items)
	print(#items)
	AuctionCache:ParseScanResults(items);
	self.buyTab.auctions = items;
	self.mode = 'auctions';

	self:UpdateSearchAuctions();
	self:UpdateStateText();
end

function Buy:UpdateStateText(inProgress)
	if inProgress then
		self.buyTab.stateLabel:SetText(L['Search in progress...']);
		self.buyTab.stateLabel:Show();
	elseif #self.buyTab.auctions == 0 and #self.buyTab.items == 0 then
		self.buyTab.stateLabel:SetText(L['Nothing was found for this query.']);
		self.buyTab.stateLabel:Show();
	else
		self.buyTab.stateLabel:Hide();
	end
end

function Buy:UpdateQueue()
	local buyTab = Buy.buyTab;
	buyTab.queueLabel:SetText(format(L['Queue Qty: %d'], ChainBuy:CalcRemainingQty()));

	buyTab.queueProgress:SetMinMaxValues(0, #ChainBuy.requests);
	buyTab.queueProgress:SetValue(ChainBuy.currentIndex);
end

function Buy:AddToFavorites()
	local searchBox = self.buyTab.searchBox;
	local text = searchBox:GetText();

	if not text or strlen(text) < 2 then
		--show error or something
		return ;
	end

	local favorites = AuctionFaster.db.favorites;
	for i = 1, #favorites do
		if favorites[i].text == text then
			--already exists - no error
			return ;
		end
	end

	TableInsert(favorites, { text = text });
	self:DrawFavorites();
end

function Buy:RemoveFromFavorites(i)
	local favorites = AuctionFaster.db.favorites;

	if favorites[i] then
		tremove(favorites, i);
	end

	self:DrawFavorites();
end

function Buy:SearchFavorite(i)
	local favorites = AuctionFaster.db.favorites;

	if favorites[i] then
		self.buyTab.searchBox:SetText(favorites[i].text);
		self:SearchAuctions(self.buyTab.searchBox:GetText(), false, 0);
	end
end

function Buy:RemoveCurrentSearchAuction()
	local index = self.buyTab.searchResults:GetSelection();
	if not index then
		return ;
	end

	if not self.buyTab.auctions[index] then
		return;
	end

	tremove(self.buyTab.auctions, index);
	self:UpdateSearchAuctions();

	if self.buyTab.auctions[index] then
		self.buyTab.searchResults:SetSelection(index);
	end
end

function Buy:UpdateSearchAuctions()
	if self.mode == 'auctions' then
		self.buyTab.searchResults:SetData(self.buyTab.auctions, true);
	else
		self.buyTab.searchResults:SetData(self.buyTab.items, true);
	end
end

function Buy:ClearSearchAuctions()
	self.buyTab.searchResults:SetData({}, true);
end

function Buy:LockBuyButton(lock)
	local buyButton = self.confirmFrame.buttons['ok'];

	if lock then
		buyButton:Disable();
	else
		buyButton:Enable();
	end
end

function Buy.CloseCallback()
	Buy:UpdateQueue();
	Buy:RefreshSearchAuctions();
end

function Buy:InstantBuy(rowData, rowIndex)
	if rowData.isCommodity then
		CommodityBuy:ConfirmPurchase(rowData.itemId);
		--Auctions:BuyItem({isCommodity = true, itemId = rowData.itemId}, 1);

		--self:RefreshSearchAuctions();
		return;
	end

	if self.mode == 'items' then
		-- TODO: ask for quantity if commodity
		Auctions:BuyItem(rowData, 1);

		self:RefreshSearchAuctions();
	else
		self:SearchItem(rowData.itemKey);
	end

	--tremove(Buy.buyTab.auctions, rowIndex);
	--self:UpdateSearchAuctions();
end

function Buy:ChainBuyStart(auctionData)
	Auctions:QueryItem(auctionData.itemKey, function(items)
		ChainBuy:Start(items, Buy.UpdateQueue, Buy.CloseCallback);
	end)
end

function Buy:AddToQueue(rowData, rowIndex)
	if not rowData then
		rowIndex = self.buyTab.searchResults:GetSelection();
		rowData = self.buyTab.searchResults:GetSelectedItem();
		if not rowData then
			AuctionFaster:Echo(3, L['Please select item first']);
			return;
		end
	end

	ChainBuy:AddBuyRequest(rowData);
	ChainBuy:Start(nil, self.UpdateQueue, self.CloseCallback);

	tremove(Buy.buyTab.auctions, rowIndex);
	Buy:UpdateSearchAuctions();
end

----------------------------------------------------------------------------
--- Filters functions
----------------------------------------------------------------------------

function Buy:GetSearchCategories()
	if self.categories and self.subCategories then
		return self.categories, self.subCategories;
	end

	local categories = {
		{value = 0, text = ALL}
	};

	local subCategories = {
		[0] = {
			{value = 0, text = ALL}
		}
	};

	for i = 1, #AuctionCategories do
		local children = AuctionCategories[i].subCategories;

		TableInsert(categories, { value = i, text = AuctionCategories[i].name});

		subCategories[i] = {};
		if children then
			TableInsert(subCategories[i], {value = 0, text = 'All'});
			for x = 1, #children do
				TableInsert(subCategories[i], {value = x, text = children[x].name});
			end
		end
	end

	self.categories = categories;
	self.subCategories = subCategories;
end

function Buy:ApplyFilters(query)
	local filters = self.filtersPane;

	query.exact = filters.exactMatch:GetChecked();
	query.isUsable = filters.usableItems:GetChecked();
	local minLevel = filters.minLevel:GetValue();
	local maxLevel = filters.maxLevel:GetValue();

	if minLevel then
		query.minLevel = minLevel;
	end

	if maxLevel then
		query.maxLevel = maxLevel;
	end

	query.qualityIndex = filters.rarity:GetValue();
	local categoryIndex = filters.category:GetValue();
	local subCategoryIndex = filters.subCategory:GetValue();

	if categoryIndex > 0 and subCategoryIndex > 0 then
		query.filterData = AuctionCategories[categoryIndex].subCategories[subCategoryIndex].filters;
	elseif categoryIndex > 0 then
		query.filterData = AuctionCategories[categoryIndex].filters;
	end
end

function Buy:InterceptLinkClick()
	if self.linksIntercepted then
		return;
	end

	local origChatEdit_InsertLink = ChatEdit_InsertLink;
	local origHandleModifiedItemClick = HandleModifiedItemClick;
	local function SearchItemLink(origMethod, link)
		if Buy.buyTab.searchBox:HasFocus() then
			local itemName = GetItemInfo(link);
			Buy.buyTab.searchBox:SetText(itemName);
			return true;
		else
			return origMethod(link);
		end
	end

	Buy:RawHook('HandleModifiedItemClick', function(link)
		return SearchItemLink(origHandleModifiedItemClick, link);
	end, true);

	Buy:RawHook('ChatEdit_InsertLink', function(link)
		return SearchItemLink(origChatEdit_InsertLink, link);
	end, true);

	self.linksIntercepted = true;
end