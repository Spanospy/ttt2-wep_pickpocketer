if SERVER then
	AddCSLuaFile()
	resource.AddFile("materials/vgui/ttt/icon_pickpocketer.vmt")
end

local sounds = {
	deny = Sound("Player.DenyWeaponSelection"),
	swing = Sound("Weapon_Crowbar.Single")
}

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.ViewModelFOV = 78
	SWEP.DrawCrosshair = false
	SWEP.ViewModelFlip = false

	SWEP.EquipMenuData = {
		type = "item_weapon",
		name = "weapon_pickpocketer_name",
		desc = "weapon_pickpocketer_desc"
	}

	SWEP.Icon = "vgui/ttt/icon_pickpocketer"
end

SWEP.Kind = WEAPON_EQUIP2
SWEP.CanBuy = {ROLE_TRAITOR}

SWEP.HoldType = "knife"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/cstrike/c_knife_t.mdl"
SWEP.WorldModel = "models/weapons/w_knife_t.mdl"

SWEP.AutoSpawnable = false
SWEP.NoSights = true

SWEP.LimitedStock = true

SWEP.Primary.Recoil = 0
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Delay = 1.1
SWEP.Primary.Ammo = "none"

SWEP.Secondary.Recoil = 0
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Delay = 1.1
SWEP.Secondary.Ammo = "none"

--SWEP.IsSilent = true

-- Pull out faster than standard guns
SWEP.DeploySpeed = 2

local sound_single = Sound("Weapon_Crowbar.Single")

function SWEP:AttemptAction()

	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
    self:SetNextSecondaryFire(CurTime() + self.Secondary.Delay)

	local owner = self:GetOwner()

	local trace = owner:GetEyeTrace()
	local distance = trace.StartPos:Distance(trace.HitPos)
	local ent = trace.Entity

	local isBody = ent:GetClass() == "prop_ragdoll" and CORPSE.IsValidBody(ent)

	self:SendWeaponAnim(ACT_VM_MISSCENTER)

	if distance < 100 and IsValid(ent) and (ent:IsPlayer() or isBody) then

		self:EmitSound(sound_single)
		return true, ent
	else
		--self:SendWeaponAnim(ACT_VM_MISSCENTER)
		return false, ent
	end

end


function SWEP:PrimaryAttack()

	local owner = self:GetOwner()

	attempt, ent = self:AttemptAction()

	if SERVER and attempt then
		StealCredits(owner, ent)
	end

end

function SWEP:SecondaryAttack()

	local owner = self:GetOwner()

	attempt, ent = self:AttemptAction()

	if SERVER and attempt then
		PlantCredits(owner, ent)
	end

end

function SWEP:Reload()
	return
end

if CLIENT then
	function SWEP:Initialize()
		self:AddTTT2HUDHelp("help_pickpocketer_primary", "help_pickpocketer_secondary")
        return self.BaseClass.Initialize(self)
	end
end

if SERVER then

	function GetCredits(ent)

		local credits = 0

		if ent:IsPlayer() then
			credits = ent:GetCredits()
		elseif ent:GetClass() == "prop_ragdoll" and CORPSE.IsValidBody(ent) then
			credits = CORPSE.GetCredits(ent, 0)
		end

		return credits

	end

	function StealCredits(ply, ent)

		local credits = GetCredits(ent)

		local stealSuccess = false --For tracking if credits has been deducted from a corpse or player

        if credits > 0 then
            if ent:IsPlayer() then
				ent:SetCredits(0)
				stealSuccess = true
			elseif ent:GetClass() == "prop_ragdoll" and CORPSE.IsValidBody(ent) then

				--In case some other addons have something to say about us taking credits
				local canTakeCredits = hook.Run("TTT2CanTakeCredits", owner, ent, false)

				ServerLog(Format("TTT2CanTakeCredits hook returned %s\n", tostring(canTakeCredits)))

				if canTakeCredits == nil then
					ServerLog("canTakeCredits defaulting to true")
					canTakeCredits = true
				end

				if canTakeCredits then
					CORPSE.SetCredits(ent, 0)
					ent.planted_credits = false
					stealSuccess = true
				else
					--And in case that addon wants to display a custom message
					local disallowed_msg = hook.Run("TTT2PickpocketMessage", owner, ent, false) or "pickpocketer_alert_disallowed"
					LANG.Msg(ply, disallowed_msg, {}, MSG_MSTACK_WARN)
				end
				
			end
            if stealSuccess then --Shared code for when either a corpse or player is stolen from
				ply:AddCredits(credits)
				LANG.Msg(ply, "pickpocketer_alert_success", {amount = credits}, MSG_MSTACK_ROLE)
			end
		else
			LANG.Msg(ply, "pickpocketer_alert_nothing", {}, MSG_MSTACK_WARN)
        end

	end

	--TODO find a way to prevent planted credits being exploited for points and event logs

	function PlantCredits(ply, ent)

		local credits = GetCredits(ent)
		local selfCredits = ply:GetCredits()

		if selfCredits > 0 then
            ply:AddCredits(-1)
			if ent:IsPlayer() then
				ent:AddCredits(1)
				LANG.Msg(ply, "pickpocketer_alert_success_plant_player", {}, MSG_MSTACK_ROLE)
			elseif ent:GetClass() == "prop_ragdoll" and CORPSE.IsValidBody(ent) then
				CORPSE.SetCredits(ent, credits + 1)
				ent.planted_credits = true
				LANG.Msg(ply, "pickpocketer_alert_success_plant_corpse", {}, MSG_MSTACK_ROLE)
			end
		else
			LANG.Msg(ply, "pickpocketer_alert_nothing_self", {}, MSG_MSTACK_WARN)
        end
	end

	hook.Add("TTT2GiveFoundCredits", "pickpocketer_planted_corpse", function(ply, rag)
		--If credits have been planted on this corpse, do what bodysearch.GiveFoundCredits would've done but without the event trigger.
		--Purpose of this is to prevent AWARDS.CreditFound abuse.
		if rag.planted_credits then

			local corpseNick = CORPSE.GetPlayerNick(rag)
			local credits = CORPSE.GetCredits(rag, 0)

			LANG.Msg(ply, "body_credits", { num = credits })

			ply:AddCredits(credits)

			CORPSE.SetCredits(rag, 0)
			rag.planted_credits = false

			ServerLog(
				ply:Nick() .. " took " .. credits .. " planted credits from the body of " .. corpseNick .. "\n"
			)

			--events.Trigger(EVENT_CREDITFOUND, ply, ent, credits)

			-- update clients so their UIs can be updated
			net.Start("ttt2_credits_were_taken")
			net.WriteUInt(searchUID or 0, 16)
			net.Broadcast()
			return false
		end
	end)
end