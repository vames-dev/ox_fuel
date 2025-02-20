if not lib.checkDependency('ox_lib', '3.0.0', true) then return end
lib.locale()

local getMyFramework = function()
	if GetResourceState('es_extended') == 'started' then
		return 'esx', exports['es_extended']:getSharedObject()

	elseif GetResourceState('qb-core') == 'started' then
		return 'qb-core', exports['qb-core']:GetCoreObject()
		
	end
end
local CoreName, Core = getMyFramework()


local function setFuelState(netid, fuel)
	local vehicle = NetworkGetEntityFromNetworkId(netid)
	local state = vehicle and Entity(vehicle)?.state

	if state then
		state:set('fuel', fuel, true)
	end
end

---@param playerId number
---@param price number
---@return boolean?
local function defaultPaymentMethod(playerId, price)
	if CoreName == 'esx' then
		local xPlayer = Core.GetPlayerFromId(playerId)
		if xPlayer.getMoney() >= price then
			xPlayer.removeMoney(price)
			return true
		else
			TriggerClientEvent('ox_lib:notify', playerId, {
				type = 'error',
				description = locale('not_enough_money', price - xPlayer.getMoney())
			})
		end
	elseif CoreName == 'qb-core' then
		local xPlayer = Core.Functions.GetPlayer(playerId)
		if xPlayer.PlayerData.money.cash >= price then
			xPlayer.Functions.RemoveMoney('cash', price)
			return true
		else
			TriggerClientEvent('ox_lib:notify', playerId, {
				type = 'error',
				description = locale('not_enough_money', price - xPlayer.PlayerData.money.cash)
			})
		end
	end
end

local payMoney = defaultPaymentMethod


RegisterNetEvent('ox_fuel:pay', function(fuel, netid, price)
	print(netid, fuel)
	
	if price ~= nil then
		if not payMoney(source, price) then
			return
		end
	end
	
	fuel = math.floor(fuel)
	setFuelState(netid, fuel)
end)

RegisterNetEvent('ox_fuel:fuelCan', function(hasCan, price)
	if hasCan then
		local item = exports.ox_inventory:GetCurrentWeapon(source)

		if not item or item.name ~= 'WEAPON_PETROLCAN' or not payMoney(source, price) then return end

		item.metadata.durability = 100
		item.metadata.ammo = 100

		exports.ox_inventory:SetMetadata(source, item.slot, item.metadata)

		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('petrolcan_refill', price)
		})
	else
		if not exports.ox_inventory:CanCarryItem(source, 'WEAPON_PETROLCAN', 1) then
			return TriggerClientEvent('ox_lib:notify', source, {
				type = 'error',
				description = locale('petrolcan_cannot_carry')
			})
		end

		if not payMoney(source, price) then return end

		exports.ox_inventory:AddItem(source, 'WEAPON_PETROLCAN', 1)

		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('petrolcan_buy', price)
		})
	end
end)

RegisterNetEvent('ox_fuel:updateFuelCan', function(durability, netid, fuel)
	local source = source
	local item = exports.ox_inventory:GetCurrentWeapon(source)
	if item and durability > 0 then
		durability = math.floor(item.metadata.durability - durability)
		item.metadata.durability = durability
		item.metadata.ammo = durability

		exports.ox_inventory:SetMetadata(source, item.slot, item.metadata)
		setFuelState(netid, fuel)
	end
end)

RegisterNetEvent('ox_fuel:createStatebag', function(netid, fuel)
	local vehicle = NetworkGetEntityFromNetworkId(netid)
	local state = vehicle and Entity(vehicle).state

	if state and not state.fuel and GetEntityType(vehicle) == 2 and NetworkGetEntityOwner(vehicle) == source then
		state:set('fuel', fuel > 100 and 100 or fuel, true)
	end
end)

RegisterServerEvent('fuel:fuelHasBeenStealed')
AddEventHandler('fuel:fuelHasBeenStealed', function(storeId, plate, fuelCount)
	exports.vms_stores:sendAnnouncement(source, storeId, (Config.StealedFuelText):format(plate, fuelCount), 'monitoring', {fuelCount = fuelCount})
end)
