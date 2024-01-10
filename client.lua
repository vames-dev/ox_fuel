if not lib.checkDependency('ox_lib', '3.0.0', true) then return end

-- if not lib.checkDependency('ox_inventory', '2.28.4', true) then return end

lib.locale()



local currentVehicle = nil
local currentStore = nil
local storeFuel = 0
local paidForFuel = false
local fuelCount = 0

AddEventHandler('vms_stores:enterStoreZone', function(storeId)
	paidForFuel = false
	currentStore = storeId
end)

RegisterNetEvent('vms_stores:fuelStoreUpdated', function(storeId, fuel)
	if currentStore == storeId and fuel then
		storeFuel = fuel
	end
end)

RegisterNetEvent('vms_stores:fuelStorePaid', function(storeId)
	local Vehicle = Entity(currentVehicle).state
	local fuel = Vehicle.fuel + fuelCount
	TriggerServerEvent('ox_fuel:pay', fuel, NetworkGetNetworkIdFromEntity(currentVehicle))
	paidForFuel = true
	fuelCount = 0
	currentVehicle = nil
end)

AddEventHandler('vms_stores:exitStoreZone', function()
	if Config.AbilityStealFuel and fuelCount > 0 then
		TriggerServerEvent('fuel:fuelHasBeenStealed', currentStore, GetVehicleNumberPlateText(currentVehicle), fuelCount)
	end
	paidForFuel = false
	currentStore = nil
	fuelCount = 0
	storeFuel = 0
	currentVehicle = nil
end)



local fuelingCan = exports.ox_inventory:getCurrentWeapon()

AddEventHandler('ox_inventory:currentWeapon', function(currentWeapon)
	fuelingCan = currentWeapon?.name == 'WEAPON_PETROLCAN' and currentWeapon
end)

local isFueling = false
local nearestPump

local nozzle, rope = nil, nil
local function nozzleObj(spawn)
	if spawn then
		local myPed = PlayerPedId()
		local myCoords = GetEntityCoords(myPed)
		local nearestPumpObj = GetClosestObjectOfType(myCoords.x, myCoords.y, myCoords.z, 3.0, 1933174915, false, false, false)
		local nearestPumpCoords = GetEntityCoords(nearestPumpObj)
		if not nearestPumpObj then
			return
		end
		RopeLoadTextures()
		rope = AddRope(
			nearestPumpCoords.x, nearestPumpCoords.y, nearestPumpCoords.z,
			0.0, -- rotX
			0.0, -- rotY
			0.0, -- rotZ
			1.0, -- maxLength
			2, -- ropeType
			1.0, -- initLength
			1.0, -- minLength
			0.0, -- lengthChangeRate
			false, -- onlyPPU
			false, -- collisionOn
			false, -- lockFromFront
			5.0, -- timeMultiplier
			false,-- breakable
		  	1
		)
		nozzle = CreateObject(joaat('prop_cs_fuel_nozle'), nearestPumpCoords.x, nearestPumpCoords.y, nearestPumpCoords.z, false, false, false) 
		AttachEntityToEntity(nozzle, myPed, GetPedBoneIndex(myPed, 18905), 0.09, 0.04, -0.01, 40.0, -90.0, -170.0, 0, false, false, false, false, true)
		StartRopeWinding(rope)
		RopeConvertToSimple(rope)
		RopeDrawShadowEnabled(rope, true)
		local myFuelPosition = GetOffsetFromEntityInWorldCoords(nozzle, 0.0, -0.0, -0.15)
		AttachEntitiesToRope(rope, nearestPumpObj, nozzle, nearestPumpCoords.x, nearestPumpCoords.y, nearestPumpCoords.z, myFuelPosition.x, myFuelPosition.y, myFuelPosition.z, 3.0, false, false, nil, nil)
	else
		DetachRopeFromEntity(rope, nozzle)
        DetachEntity(nozzle, true, false)
        DeleteEntity(nozzle)
        DeleteRope(rope)
		nozzle = nil
		rope = nil
	end
end

local function getVehicleInFront()
    local coords = GetEntityCoords(cache.ped)
	local destination = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.2, -0.25)
    local handle = StartShapeTestCapsule(coords.x, coords.y, coords.z, destination.x, destination.y, destination.z, 2.2, 2, cache.ped, 4)

    while true do
        Wait(0)
        local retval, _, _, _, entityHit = GetShapeTestResult(handle)

        if retval ~= 1 then
            return entityHit ~= 0 and entityHit
        end
    end
end

local function setFuel(state, vehicle, fuel, replicate)
	if DoesEntityExist(vehicle) then
		if fuel < 0 then fuel = 0 end
		SetVehicleFuelLevel(vehicle, fuel)
		if not state.fuel then
			TriggerServerEvent('ox_fuel:createStatebag', NetworkGetNetworkIdFromEntity(vehicle), fuel)
		else
			state:set('fuel', fuel, replicate)
		end
	end
end

local lastVehicle = cache.vehicle or GetPlayersLastVehicle()

lib.onCache('seat', function(seat)
	if cache.vehicle then
		lastVehicle = cache.vehicle
	end

	if not NetworkGetEntityIsNetworked(lastVehicle) then return end

	if seat == -1 then
		SetTimeout(0, function()
			local vehicle = cache.vehicle
			local multiplier = Config.classUsage[GetVehicleClass(vehicle)] or 1.0

			-- Vehicle doesn't use fuel
			if multiplier == 0.0 then return end

			local state = Entity(vehicle).state

			if not state.fuel then
				TriggerServerEvent('ox_fuel:createStatebag', NetworkGetNetworkIdFromEntity(vehicle), GetVehicleFuelLevel(vehicle))
				while not state.fuel do Wait(0) end
			end

			SetVehicleFuelLevel(vehicle, state.fuel)

			local fuelTick = 0

			while cache.seat == -1 do
				local fuel = state.fuel
				local newFuel = fuel

				if fuel > 0 then
					if GetIsVehicleEngineRunning(vehicle) then
						local usage = Config.rpmUsage[math.floor(GetVehicleCurrentRpm(vehicle) * 10) / 10]
						newFuel -= usage * multiplier
					end

					if GetVehiclePetrolTankHealth(vehicle) < 700 then
						newFuel -= math.random(10, 20) * 0.01
					end

					if fuel ~= newFuel then
						if fuelTick == 15 then
							fuelTick = 0
						end

						setFuel(state, vehicle, newFuel, fuelTick == 0)
						fuelTick += 1
					end
				end

				Wait(1000)
			end

			setFuel(state, vehicle, state.fuel, true)
		end)
	end
end)

AddTextEntry('ox_fuel_station', locale('fuel_station_blip'))

local function createBlip(station)
	local blip = AddBlipForCoord(station.x, station.y, station.z)
	SetBlipSprite(blip, 361)
	SetBlipDisplay(blip, 4)
	SetBlipScale(blip, 0.8)
	SetBlipColour(blip, 6)
	SetBlipAsShortRange(blip, true)
	BeginTextCommandSetBlipName('ox_fuel_station')
	EndTextCommandSetBlipName(blip)

	return blip
end

CreateThread(function()
	local blip

	if Config.ox_target and Config.showBlips ~= 1 then return end

	while true do
		local playerCoords = GetEntityCoords(cache.ped)

		for station, pumps in pairs(stations) do
			local stationDistance = #(playerCoords - station)
			if stationDistance < 60 then
				if Config.showBlips == 1 and not blip then
					blip = createBlip(station)
				end

				if not Config.ox_target then
					repeat
						if stationDistance < 15 then
							local pumpDistance

							repeat
								playerCoords = GetEntityCoords(cache.ped)
								for i = 1, #pumps do
									local pump = pumps[i]
									pumpDistance = #(playerCoords - pump)

									if pumpDistance < 3 then
										nearestPump = pump

										while pumpDistance < 3 do
											if cache.vehicle then
												DisplayHelpTextThisFrame('fuelLeaveVehicleText', false)
											elseif not isFueling then
												local vehicleInRange = lastVehicle ~= 0 and #(GetEntityCoords(lastVehicle) - playerCoords) <= 3

												if vehicleInRange then
													DisplayHelpTextThisFrame('fuelHelpText', false)
												elseif Config.petrolCan.enabled then
													DisplayHelpTextThisFrame('petrolcanHelpText', false)
												end
											end

											pumpDistance = #(GetEntityCoords(cache.ped) - pump)
											Wait(0)
										end

										nearestPump = nil
									end
								end
								Wait(100)
							until pumpDistance > 15
							break
						end

						Wait(100)
						stationDistance = #(GetEntityCoords(cache.ped) - station)
					until stationDistance > 60
				end
			end
		end


		Wait(500)
		if blip then
			RemoveBlip(blip)
			blip = nil
		end
	end
end)

if Config.showBlips == 2 then
	for station in pairs(stations) do createBlip(station) end
end

-- local ox_inventory = exports.ox_inventory

-- ---@return number
local function defaultMoneyCheck()
	return 300000
	-- return ox_inventory:Search('count', 'money')
end

local getMoneyAmount = defaultMoneyCheck

exports('setMoneyCheck', function(fn)
	getMoneyAmount = fn or defaultMoneyCheck
end)

-- fuelingMode = 1 - Pump
-- fuelingMode = 2 - Can
local function startFueling(vehicle, isPump)
	if not Config.AbilityStealFuel and currentVehicle ~= nil and currentVehicle ~= vehicle then
		lib.notify({type = 'error', description = locale('cant_refuel_multiple_cars')})
		return
	end

	local Vehicle = Entity(vehicle).state
	local fuel = Vehicle.fuel or GetVehicleFuelLevel(vehicle)
	local duration = math.ceil((100 - fuel) / Config.refillValue) * Config.refillTick
	local price, moneyAmount
	local durability = 0

	if 100 - fuel < Config.refillValue then
		return lib.notify({type = 'error', description = locale('tank_full')})
	end

	if isPump then
		price = 0
		moneyAmount = getMoneyAmount()

		if storeFuel <= 0 then
			return lib.notify({
				type = 'error',
				description = locale('not_enough_fuel')
			})
		end
		currentVehicle = vehicle
		if Config.priceTick > moneyAmount then
			return lib.notify({
				type = 'error',
				description = locale('not_enough_money', Config.priceTick)
			})
		end
	elseif not fuelingCan then
		return lib.notify({type = 'error', description = locale('petrolcan_not_equipped')})
	elseif fuelingCan.metadata.ammo <= Config.durabilityTick then
		return lib.notify({
			type = 'error',
			description = locale('petrolcan_not_enough_fuel')
		})
	end

	isFueling = true
	nozzleObj(true)

	TaskTurnPedToFaceEntity(cache.ped, vehicle, duration)
	Wait(500)

	CreateThread(function()
		lib.progressCircle({
			duration = duration,
			useWhileDead = false,
			canCancel = true,
			disable = {
				move = true,
				car = true,
				combat = true,
			},
			anim = {
				dict = isPump and 'timetable@gardener@filling_can' or 'weapon@w_sp_jerrycan',
				clip = isPump and 'gar_ig_5_filling_can' or 'fire',
			},
		})
		nozzleObj(false)
		isFueling = false
	end)

	while isFueling do
		if isPump then
			price += Config.priceTick

			if price + Config.priceTick >= moneyAmount then
				lib.cancelProgress()
			end
		else
			durability += Config.durabilityTick

			if durability >= fuelingCan.metadata.ammo then
				lib.cancelProgress()
				durability = fuelingCan.metadata.ammo
				break
			end
		end

		local ranOutOfFuel = exports['vms_stores']:addFuelToCart(Config.refillValue)
		if ranOutOfFuel then
			lib.cancelProgress()
			break
		end

		fuelCount += Config.refillValue
		fuel += Config.refillValue


		if fuel >= 100 then
			isFueling = false
			fuel = 100.0
		end

		Wait(Config.refillTick)
	end

	ClearPedTasks(cache.ped)

	if isPump then
		if Config.AbilityStealFuel then
			TriggerServerEvent('ox_fuel:pay', fuel, NetworkGetNetworkIdFromEntity(vehicle))
		end
	else
		TriggerServerEvent('ox_fuel:updateFuelCan', durability, NetworkGetNetworkIdFromEntity(vehicle), fuel)
	end
end


local function getPetrolCan(pumpCoord, refuel)
	if not Config.petrolCan.enabled then
		return
	end
	TaskTurnPedToFaceCoord(cache.ped, pumpCoord.x, pumpCoord.y, pumpCoord.z, Config.petrolCan.duration)
	Wait(500)

	if lib.progressCircle({
		duration = Config.petrolCan.duration,
		useWhileDead = false,
		canCancel = true,
		disable = {
			move = true,
			car = true,
			combat = true,
		},
		anim = {
			dict = 'timetable@gardener@filling_can',
			clip = 'gar_ig_5_filling_can',
			flags = 49,
		}
	}) then
		if refuel and ox_inventory:Search('count', 'WEAPON_PETROLCAN') then
			return TriggerServerEvent('ox_fuel:fuelCan', true, Config.petrolCan.refillPrice)
		end

		TriggerServerEvent('ox_fuel:fuelCan', false, Config.petrolCan.price)
	end

	ClearPedTasks(cache.ped)
end

local bones = {
	'petrolcap',
	'petroltank',
	'petroltank_l',
	'hub_lr',
	'engine',
}

local function getVehiclePetrolCapBoneIndex(vehicle)
	for i = 1, #bones do
		local boneIndex = GetEntityBoneIndexByName(vehicle, bones[i])
		if boneIndex ~= -1 then
			return boneIndex
		end
	end
end

if not Config.ox_target then
	RegisterCommand('startfueling', function()
		if isFueling or cache.vehicle or lib.progressActive() then return end

		local petrolCan = Config.petrolCan.enabled and GetSelectedPedWeapon(cache.ped) == `WEAPON_PETROLCAN`
		local playerCoords = GetEntityCoords(cache.ped)

		if nearestPump then
			local moneyAmount = getMoneyAmount()

			if petrolCan and moneyAmount >= Config.petrolCan.refillPrice then
				return getPetrolCan(nearestPump, true)
			end

			local vehicleInRange = lastVehicle and #(GetEntityCoords(lastVehicle) - playerCoords) <= 3

			if not vehicleInRange then
				if not Config.petrolCan.enabled then return end
				if moneyAmount >= Config.petrolCan.price then
					return getPetrolCan(nearestPump)
				end
				return lib.notify({type = 'error', description = locale('petrolcan_cannot_afford')})
			else
				return startFueling(lastVehicle, true)
			end

			return lib.notify({type = 'error', description = locale('vehicle_far')})
		elseif petrolCan then
			local vehicle = getVehicleInFront()

			if vehicle then
				local hasFuel = Config.classUsage[GetVehicleClass(vehicle)] or true

				if hasFuel == 0.0 then return end

				local boneIndex = getVehiclePetrolCapBoneIndex(vehicle)
				local fuelcapPosition = boneIndex and GetWorldPositionOfEntityBone(vehicle, boneIndex)

				if fuelcapPosition and #(playerCoords - fuelcapPosition) < 1.8 then
					return startFueling(vehicle, false)
				end

				return lib.notify({type = 'error', description = locale('vehicle_far')})
			end
		end
	end)

	RegisterKeyMapping('startfueling', 'Fuel vehicle', 'keyboard', 'e')
	TriggerEvent('chat:removeSuggestion', '/startfueling')
end


if Config.ox_target then
	if Config.petrolCan.enabled then
		exports.ox_target:addModel(Config.pumpModels, {
			{
				distance = 2,
				onSelect = function()
					if getMoneyAmount() >= Config.priceTick then
						startFueling(lastVehicle, 1)
					else
						lib.notify({type = 'error', description = locale('refuel_cannot_afford')})
					end
				end,
				icon = "fas fa-gas-pump",
				label = locale('start_fueling'),
				canInteract = function(entity)
					if isFueling or cache.vehicle or lib.progressActive() then
						return false
					end

					return lastVehicle and #(GetEntityCoords(lastVehicle) - GetEntityCoords(cache.ped)) <= 3
				end
			},
			{
				distance = 2,
				onSelect = function(data)
					local petrolCan = Config.petrolCan.enabled and GetSelectedPedWeapon(cache.ped) == `WEAPON_PETROLCAN`
					local moneyAmount = getMoneyAmount()

					if moneyAmount < Config.petrolCan.price then
						return lib.notify({type = 'error', description = locale('petrolcan_cannot_afford')})
					end

					return getPetrolCan(data.coords, petrolCan)
				end,
				icon = "fas fa-faucet",
				label = locale('petrolcan_buy_or_refill'),
			},
		})
	else
		exports.ox_target:addModel(Config.pumpModels, {
			{
				distance = 2,
				onSelect = function()
					if getMoneyAmount() >= Config.priceTick then
						if GetVehicleFuelLevel(lastVehicle) >= 100 then
							return lib.notify({type = 'error', description = locale('vehicle_full')})
						end
						startFueling(lastVehicle, 1)
					else
						lib.notify({type = 'error', description = locale('refuel_cannot_afford')})
					end
				end,
				icon = "fas fa-gas-pump",
				label = locale('start_fueling'),
				canInteract = function(entity)
					if isFueling or cache.vehicle then
						return false
					end

					return lastVehicle and #(GetEntityCoords(lastVehicle) - GetEntityCoords(cache.ped)) <= 3
				end
			},
		})
	end
	if Config.petrolCan.enabled then
		exports.ox_target:addGlobalVehicle({
			{
				distance = 2,
				onSelect = function(data)
					if not fuelingCan then
						return lib.notify({type = 'error', description = locale('petrolcan_not_equipped')})
					end

					if fuelingCan.metadata.ammo <= Config.durabilityTick then
						return lib.notify({
							type = 'error',
							description = locale('petrolcan_not_enough_fuel')
						})
					end

					startFueling(data.entity)
				end,
				icon = "fas fa-gas-pump",
				label = locale('start_fueling'),
				canInteract = function(entity)
					if isFueling or cache.vehicle or lib.progressActive() then
						return false
					end
					return fuelingCan and Config.petrolCan.enabled
				end
			}
		})
	end
end

AddTextEntry('fuelHelpText', locale('fuel_help'))
AddTextEntry('petrolcanHelpText', locale('petrolcan_help'))
AddTextEntry('fuelLeaveVehicleText', locale('leave_vehicle'))
