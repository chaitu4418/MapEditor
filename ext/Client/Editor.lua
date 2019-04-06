class 'Editor'

local m_Logger = Logger("Editor", true)
local m_InstanceParser = require "InstanceParser"


local MAX_CAST_DISTANCE = 10000
local FALLBACK_DISTANCE = 10

function Editor:__init()
	m_Logger:Write("Initializing EditorClient")
	self:RegisterVars()

end

function Editor:RegisterVars()
	self.m_PendingRaycast = false
    self.m_FreecamMoving = false

	self.m_Commands = {
		SpawnBlueprintCommand = Backend.SpawnBlueprint,
		DestroyBlueprintCommand = Backend.DestroyBlueprint,
		SetTransformCommand = Backend.SetTransform,
		SelectGameObjectCommand = Backend.SelectGameObject,
		CreateGroupCommand = Backend.CreateGroup,
	}

	self.m_Changes = {
		reference = "SpawnBlueprintCommand",
		destroyed = "DestroyBlueprintCommand",
		transform = "SetTransformCommand",
	}

	self.m_Messages = {
		MoveObjectMessage = self.MoveObject,
		SetViewModeMessage = self.SetViewMode,
		SetScreenToWorldPositionMessage = self.SetScreenToWorldPosition,
		PreviewSpawnMessage = self.PreviewSpawn,
		PreviewDestroyMessage = self.PreviewDestroy,
		PreviewMoveMessage = self.PreviewMove
	}

	self.m_Queue = {
        commands = {},
        messages = {}
    };

	self.m_TransactionId = 0
	self.m_GameObjects = {}
    self.m_VanillaObjects = {}
	self.m_VanillaUnresolved = {}
end

function Editor:OnPartitionLoaded(p_Partition)
    m_InstanceParser:OnPartitionLoaded(p_Partition)
end

function Editor:OnLevelLoaded(p_MapName, p_GameModeName)
	m_InstanceParser:OnLevelLoaded(p_MapName, p_GameModeName)
end

function Editor:OnEngineMessage(p_Message)
	if p_Message.type == MessageType.ClientLevelFinalizedMessage then
		m_InstanceParser:FillVariations()
		local s_LevelDatas = m_InstanceParser:GetLevelDatas()

		for k,v in pairs(s_LevelDatas) do
			WebUI:ExecuteJS(string.format("editor.gameContext.LoadLevel('%s')", json.encode(v)))
		end
		print("Unresolved: " .. #self.m_VanillaUnresolved)

		WebUI:ExecuteJS(string.format("editor.blueprintManager.RegisterBlueprints('%s')", json.encode(m_InstanceParser.m_Blueprints)))
        WebUI:ExecuteJS(string.format("editor.vext.HandleResponse('%s')", json.encode(self.m_VanillaObjects)))
        WebUI:ExecuteJS(string.format("console.log('%s')", json.encode(self.m_VanillaUnresolved)))

    end
	if p_Message.type == MessageType.ClientCharacterLocalPlayerSetMessage then
		local s_LocalPlayer = PlayerManager:GetLocalPlayer()

		if s_LocalPlayer == nil then
			m_Logger:Error("Local player is nil")
			return
		end
		m_Logger:Write("Requesting update")
		NetEvents:SendLocal("MapEditorServer:RequestUpdate", 1)
		WebUI:ExecuteJS(string.format("editor.setPlayerName('%s')", s_LocalPlayer.name))
	end
end

function Editor:OnReceiveUpdate(p_Update)
	local s_Responses = {}

	for s_Guid, v in pairs(p_Update) do
		if(self.m_GameObjects[s_Guid] == nil) then
			local s_StringGuid = tostring(s_Guid)

			--If it's a vanilla object we move it or we delete it. If not we spawn a new object.
			if IsVanillaGuid(s_StringGuid)then
				local s_Command = nil

				if v.isDeleted then
					s_Command = {
						type = "DestroyBlueprintCommand",
						guid = s_Guid,

					}
				else
					s_Command = {

						type = "SetTransformCommand",
						guid = s_Guid,
						userData = p_Update[s_Guid]
					}
				end
				table.insert(s_Responses, s_Command)
			else
				local s_Command = {
					type = "SpawnBlueprintCommand",
					guid = s_Guid,
					userData = p_Update[s_Guid]
				}
				table.insert(s_Responses, s_Command)
			end
		else
			local s_Changes = GetChanges(self.m_GameObjects[s_Guid], p_Update[s_Guid])
			-- Hopefully this will never happen. It's hard to test these changes since they require a desync.
			if(#s_Changes > 0) then
				m_Logger:Write("--------------------------------------------------------------------")
				m_Logger:Write("If you ever see this, please report it on the repo.")
				m_Logger:Write(s_Changes)
				m_Logger:Write("--------------------------------------------------------------------")
			end
		end

	end
	self:OnReceiveCommand(s_Responses, true)
end

function Editor:OnUpdate(p_Delta, p_SimulationDelta)
    if(self.m_FreecamMoving) then
        self:UpdateCameraTransform()
    end
	-- Raycast has to be done in update
	self:Raycast()
end


function Editor:OnSendToServer(p_Command)
	NetEvents:SendLocal('MapEditorServer:ReceiveCommand', p_Command)
end

function Editor:OnReceiveCommand(p_Command, p_Raw, p_UpdatePass)
	local s_Command = p_Command
	if p_Raw == nil then
		s_Command = DecodeParams(json.decode(p_Command))
	end

	local s_Responses = {}
	for k, l_Command in ipairs(s_Command) do
		local s_Function = self.m_Commands[l_Command.type]
		if(s_Function == nil) then
			m_Logger:Error("Attempted to call a nil function: " .. l_Command.type)
			return false
		end
		local s_Response = s_Function(self, l_Command, p_UpdatePass)
		if(s_Response == false) then
			-- TODO: Handle errors
			m_Logger:Error("error")
		elseif(s_Response == "queue") then
			m_Logger:Write("Queued command")
			table.insert(self.m_Queue.commands, l_Command)
		else
			local s_Transform = LinearTransform()
			if s_Response.userData ~= nil then
				s_Transform = s_Response.userData.transform
			end
			self.m_GameObjects[l_Command.guid] = {
				isDeleted = s_Response.isDeleted or false,
				transform = s_Transform
			}
			table.insert(s_Responses, s_Response)
		end
	end
	m_Logger:Write(json.encode(self.m_GameObjects))
	if(#s_Responses > 0) then
		WebUI:ExecuteJS(string.format("editor.vext.HandleResponse('%s')", json.encode(s_Responses)))
	end
end

function Editor:OnReceiveMessage(p_Messages, p_Raw, p_UpdatePass)
    local s_Messages = p_Messages
    if p_Raw == nil then
        s_Messages = DecodeParams(json.decode(p_Messages))
    end
    for k, l_Message in ipairs(s_Messages) do


        local s_Function = self.m_Messages[l_Message.type]
        if(s_Function == nil) then
            m_Logger:Error("Attempted to call a nil function: " .. l_Message.type)
            return false
        end

        local s_Response = s_Function(self, l_Message, p_UpdatePass)

        if(s_Response == false) then
            -- TODO: Handle errors
            m_Logger:Error("error")
        elseif(s_Response == "queue") then
            m_Logger:Write("Queued message")
            table.insert(self.m_Queue.messages, l_Message)
        elseif(s_Response == true) then
            --TODO: Success message?
        end
    end

	-- Messages don't respond
end

function Editor:OnUpdatePass(p_Delta, p_Pass)
    if(p_Pass ~= UpdatePass.UpdatePass_PreSim or (#self.m_Queue.commands == 0 and #self.m_Queue.messages == 0)) then
        return
    end
    local s_Commands = {}
    for k,l_Command in ipairs(self.m_Queue.commands) do
        m_Logger:Write("Executing command in the correct UpdatePass: " .. l_Command.type)
        table.insert(s_Commands, l_Command)
    end

    self:OnReceiveCommand(s_Commands, true, p_Pass)

    local s_Messages = {}
    for k,l_Message in ipairs(self.m_Queue.messages) do
        m_Logger:Write("Executing message in the correct UpdatePass: " .. l_Message.type)
        table.insert(s_Messages, l_Message)
    end

    self:OnReceiveMessage(s_Messages, true, p_Pass)

    if(#self.m_Queue.commands > 0) then
        self.m_Queue.commands = {}
    end
    if(#self.m_Queue.messages > 0) then
        self.m_Queue.messages = {}
    end
end

--[[

	Messages

--]]

function Editor:MoveObject(p_Message)
	return ObjectManager:SetTransform(p_Message.guid, p_Message.transform, false)
end

function Editor:SetViewMode(p_Message)
	local p_WorldRenderSettings = ResourceManager:GetSettings("WorldRenderSettings")
	if p_WorldRenderSettings ~= nil then
		local s_WorldRenderSettings = WorldRenderSettings(p_WorldRenderSettings)
		s_WorldRenderSettings.viewMode = p_Message.viewMode
	else
		m_Logger:Error("Failed to get WorldRenderSettings")
		return false;
		-- Notify WebUI
	end
end

function Editor:SetScreenToWorldPosition(p_Message)
	self:SetPendingRaycast(RaycastType.Mouse, p_Message.direction)
end

function Editor:PreviewSpawn(p_Message, p_Arguments)
    local s_UserData = p_Message.userData
    return ObjectManager:SpawnBlueprint(p_Message.guid, s_UserData.reference.partitionGuid, s_UserData.reference.instanceGuid, s_UserData.transform, s_UserData.variation)
end
function Editor:PreviewDestroy(p_Message, p_UpdatePass)
    if(p_UpdatePass ~= UpdatePass.UpdatePass_PreSim) then
        return "queue"
    end

    return ObjectManager:DestroyEntity(p_Message.guid)
end
function Editor:PreviewMove(p_Message, p_Arguments)
    return ObjectManager:SetTransform(p_Message.guid, p_Message.transform, false)
end
--[[

	Shit

--]]
function Editor:OnEntityCreateFromBlueprint(p_Hook, p_Blueprint, p_Transform, p_Variation, p_Parent )
    --Avoid nested blueprints for now...
	local s_PartitionGuid = m_InstanceParser:GetPartition(p_Blueprint.instanceGuid)
	local s_ParentPartition = nil
	local s_ParentPrimaryInstance = nil
	local s_ParentType = nil
	if(p_Parent ~= nil) then
		s_ParentPartition = m_InstanceParser:GetPartition(p_Parent.instanceGuid)
		s_ParentPrimaryInstance = m_InstanceParser:GetPrimaryInstance(s_ParentPartition)
		local s_Parent = ResourceManager:FindInstanceByGUID(Guid(s_ParentPartition), Guid(s_ParentPrimaryInstance))
		s_ParentType = s_Parent.typeInfo.name
	else
		print(p_Blueprint.instanceGuid)
		s_ParentPartition = "dynamic"
		s_ParentPrimaryInstance = "dynamic"
	end
	local s_Response = Backend:BlueprintSpawned(p_Hook, p_Blueprint, p_Transform, p_Variation, p_Parent, s_PartitionGuid, s_ParentPartition, s_ParentPrimaryInstance, s_ParentType)

	-- Check if the current blueprint is referenced from a leveldata
	if(m_InstanceParser:GetLevelData(s_ParentPrimaryInstance) ~= nil) then
		s_Response.parentGuid = s_ParentPrimaryInstance
		table.insert(self.m_VanillaObjects, s_Response)
	else
		print(m_InstanceParser:GetLevelDatas())
	end
		-- Check if the current blueprint is referenced by earlier blueprints
	if(self.m_VanillaUnresolved[tostring(p_Blueprint.instanceGuid)] ~= nil) then
		-- Loop through all the children that are referencing this blueprint and assign this as their parent.
		for k,v in pairs(self.m_VanillaUnresolved[tostring(p_Blueprint.instanceGuid)]) do
			v.parentGuid = s_Response.guid
			table.insert(self.m_VanillaObjects, v)
		end
		self.m_VanillaUnresolved[tostring(p_Blueprint.instanceGuid)] = nil
		-- If the current blueprint don't have a parent assigned, add it to the unresolved list
		if(s_Response.parentGuid == nil) then
			-- Add the current blueprint to the unresolved list.
			if(self.m_VanillaUnresolved[s_ParentPrimaryInstance] == nil) then
				self.m_VanillaUnresolved[s_ParentPrimaryInstance] = {}
			end
			table.insert(self.m_VanillaUnresolved[s_ParentPrimaryInstance],s_Response)
		end
	else -- Blueprint has arrived before the parent. Add it to the unresolved list.
		if(self.m_VanillaUnresolved[s_ParentPrimaryInstance] == nil) then
			self.m_VanillaUnresolved[s_ParentPrimaryInstance] = {}
		end
		table.insert(self.m_VanillaUnresolved[s_ParentPrimaryInstance], s_Response)
	end
end



function Editor:OnEntityCreate(p_Hook, p_Data, p_Transform)
    if p_Data == nil then
        m_Logger:Error("Didnt get no data")
    else
        local s_Entity = p_Hook:Call(p_Data, p_Transform)
        local s_PartitionGuid = m_InstanceParser:GetPartition(p_Data.instanceGuid)
        if(s_PartitionGuid == nil) then
            return
        end
        local s_Partition = ResourceManager:FindDatabasePartition(Guid(s_PartitionGuid))
        if(s_Partition == nil) then
            return
        end
    end
end

function Editor:Raycast()
	if not self.m_PendingRaycast then
		return
	end

	local s_Transform = ClientUtils:GetCameraTransform()
	local s_Direction = self.m_PendingRaycast.direction

	if(self.m_PendingRaycast.type == RaycastType.Camera) then
		s_Direction = Vec3(s_Transform.forward.x * -1, s_Transform.forward.y * -1, s_Transform.forward.z * -1)
	end


	if s_Transform.trans == Vec3(0,0,0) then -- Camera is below the ground. Creating an entity here would be useless.
		return
	end

	-- The freecam transform is inverted. Invert it back
	local s_CastPosition = Vec3(s_Transform.trans.x + (s_Direction.x * MAX_CAST_DISTANCE),
								s_Transform.trans.y + (s_Direction.y * MAX_CAST_DISTANCE),
								s_Transform.trans.z + (s_Direction.z * MAX_CAST_DISTANCE))

	local s_Raycast = RaycastManager:Raycast(s_Transform.trans, s_CastPosition, 2)

	if s_Raycast ~= nil then
		s_Transform.trans = s_Raycast.position
	else

		-- Raycast didn't hit anything. Spawn it in front of the player instead.
		s_Transform.trans = Vec3(s_Transform.trans.x + (s_Direction.x * FALLBACK_DISTANCE),
							s_Transform.trans.y + (s_Direction.y * FALLBACK_DISTANCE),
							s_Transform.trans.z + (s_Direction.z * FALLBACK_DISTANCE))
	end
	if(self.m_PendingRaycast.type == RaycastType.Camera) then
		WebUI:ExecuteJS(string.format('editor.SetRaycastPosition(%s, %s, %s)',
				s_Transform.trans.x, s_Transform.trans.y, s_Transform.trans.z))
	end
	if(self.m_PendingRaycast.type == RaycastType.Mouse) then
		WebUI:ExecuteJS(string.format('editor.SetScreenToWorldPosition(%s, %s, %s)',
				s_Transform.trans.x, s_Transform.trans.y, s_Transform.trans.z))
	end
			
	self.m_PendingRaycast = false

end

function Editor:UpdateCameraTransform()
	local s_Transform = ClientUtils:GetCameraTransform()
	local pos = s_Transform.trans

	local left = s_Transform.left
	local up = s_Transform.up
	local forward = s_Transform.forward

	WebUI:ExecuteJS(string.format('editor.threeManager.UpdateCameraTransform(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);',
		left.x, left.y, left.z, up.x, up.y, up.z, forward.x, forward.y, forward.z, pos.x, pos.y, pos.z))

end

function Editor:SetPendingRaycast(p_Type, p_Direction)
	self.m_PendingRaycast = {
		type = p_Type,
		direction = p_Direction
	}
end


return Editor()