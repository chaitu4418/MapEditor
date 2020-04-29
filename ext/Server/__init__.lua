class 'MapEditorServer'

local m_Logger = Logger("MapEditorServer", true)

ServerTransactionManager = require "ServerTransactionManager"
ProjectManager = require "ProjectManager"
DataBaseManager = require "DataBaseManager"
ServerGameObjectManager = require "ServerGameObjectManager"
GameObjectManager = GameObjectManager(Realm.Realm_Server)
--VanillaBlueprintsParser = VanillaBlueprintsParser(Realm.Realm_Client)
InstanceParser = InstanceParser(Realm.Realm_Server)
CommandActions = CommandActions(Realm.Realm_ClientAndServer)
EditorCommon = EditorCommon(Realm.Realm_ClientAndServer)

local presetJSON = require "preset"
local preset = json.decode(presetJSON)

function MapEditorServer:__init()
	m_Logger:Write("Initializing MapEditorServer")
	self:RegisterEvents()
end

function MapEditorServer:RegisterEvents()
	NetEvents:Subscribe('EnableInputRestriction', self, self.OnEnableInputRestriction)
	NetEvents:Subscribe('DisableInputRestriction', self, self.OnDisableInputRestriction)

	Events:Subscribe('UpdateManager:Update', self, self.OnUpdatePass)
	Events:Subscribe('Level:Destroy', self, self.OnLevelDestroy)
    Events:Subscribe('Level:Loaded', self, self.OnLevelLoaded)
    Events:Subscribe('Partition:Loaded', self, self.OnPartitionLoaded)
	Events:Subscribe('Player:Chat', self, self.OnChat)
	Events:Subscribe('Player:Authenticated', self, self.OnPlayerAuthenticated)

	Events:Subscribe('GameObjectManager:GameObjectReady', self, self.OnGameObjectReady)

	Hooks:Install('ResourceManager:LoadBundles', 999, self, self.OnLoadBundles)
    Hooks:Install('EntityFactory:CreateFromBlueprint', 999, self, self.OnEntityCreateFromBlueprint)
end

----------- Debug ----------------

function string:split(sep)
	local sep, fields = sep or ":", {}
	local pattern = string.format("([^%s]+)", sep)
	self:gsub(pattern, function(c) fields[#fields+1] = c end)
	return fields
 end

function MapEditorServer:OnChat(p_Player, p_RecipientMask, p_Message)
	if p_Message == '' then
		return
	end

	if p_Player == nil then
		return
	end

	m_Logger:Write('Chat: ' .. p_Message)

	p_Message = p_Message:lower()

	local s_Parts = p_Message:split(' ')
	local firstPart = s_Parts[1]

	if firstPart == 'save' then
		ServerTransactionManager:OnRequestProjectSave(p_Player, "DebugProject", "XP3_Shield", "ConquestLarge0", { "levels/mp_001/mp_001", "levels/mp_001/conquest" })
	end
end

----------- Game functions----------------
function MapEditorServer:OnUpdatePass(p_Delta, p_Pass)
	ServerTransactionManager:OnUpdatePass(p_Delta, p_Pass)
	ProjectManager:OnUpdatePass(p_Delta, p_Pass)
end

function MapEditorServer:OnLevelLoaded(p_Map, p_GameMode, p_Round)
	--ServerTransactionManager:OnLevelLoaded(p_Map, p_GameMode, p_Round)
	if preset == nil then
		print("FUCK")
	end

	if preset.header == nil or preset.header.mapName == nil then
		print("FUCK v2")
	end
	ProjectManager:OnLevelLoaded(p_Map, p_GameMode, p_Round)
	if string.find(p_Map:lower(), preset.header.mapName:lower()) then
		print("FOUND DUST2")
	end

	local commands = {}

	for key, v in pairs(preset.data) do
		local a = DecodeParams(v)
		local command = {}
		command.type = "SpawnBlueprintCommand"
		command.sender = ""
		command.gameObjectTransferData = {
			guid = key,
			parentData = v.parentData,
			blueprintCtrRef = v.blueprintCtrRef,
			transform = v.transform,
			variation = v.variation
		}
		table.insert(commands, command)
	end
	print(#commands)
	ServerTransactionManager:ExecuteCommands(commands, 0)
end

function MapEditorServer:OnLevelDestroy()
	m_Logger:Write("Destroy!")
	GameObjectManager:OnLevelDestroy()
end

function MapEditorServer:OnPartitionLoaded(p_Partition)
	InstanceParser:OnPartitionLoaded(p_Partition)
	EditorCommon:OnPartitionLoaded(p_Partition)
end

function MapEditorServer:OnEntityCreateFromBlueprint(p_Hook, p_Blueprint, p_Transform, p_Variation, p_Parent )
	GameObjectManager:OnEntityCreateFromBlueprint(p_Hook, p_Blueprint, p_Transform, p_Variation, p_Parent )
end

function MapEditorServer:OnLoadBundles(p_Hook, p_Bundles, p_Compartment)
	EditorCommon:OnLoadBundles(p_Hook, p_Bundles, p_Compartment, ProjectManager.m_CurrentProjectHeader)
end

function MapEditorServer:OnPlayerAuthenticated(p_Player)

end

function MapEditorServer:SetInputRestriction(p_Player, p_Enabled)
	for i=0, 125 do
		p_Player:EnableInput(i, p_Enabled)
	end
end
----------- Editor functions----------------

function MapEditorServer:OnGameObjectReady(p_GameObject)
	--ServerTransactionManager:OnGameObjectReady(p_GameObject)
end

function MapEditorServer:OnEnableInputRestriction(p_Player)
	self:SetInputRestriction(p_Player, false)
end

function MapEditorServer:OnDisableInputRestriction(p_Player)
	self:SetInputRestriction(p_Player, true)
end

return MapEditorServer()
