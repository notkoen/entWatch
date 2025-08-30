//====================================================================================================
//
// Name: [entWatch] Forcedrop
// Author: zaCade & Prometheum
// Description: Handle the forced dropping of weapons of [entWatch]
//
//====================================================================================================
// Requires Sourcemod Version: ?
//====================================================================================================
#pragma semicolon 1
#pragma newdecls required

#include <dhooks>
#include <entWatch_core>
#include <sourcemod>
#include <sdkhooks>

Handle SDKCall_GetSlot;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Forcedrop",
	author       = "zaCade & Prometheum",
	description  = "Handle the forced dropping of weapons for [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadGameConfig();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Loads GameData
//----------------------------------------------------------------------------------------------------
stock void LoadGameConfig()
{
	GameData hGameConf;
	if ((hGameConf = new GameData("entWatch.games")) == null)
	{
		SetFailState("Failed to load \"entWatch.games\" game config!");
		return;
	}

	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::GetSlot"))
	{
		delete hGameConf;
		SetFailState("Failed to setup SDKCall \"SDKCall_GetSlot\"!");
		return;
	}

	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((SDKCall_GetSlot = EndPrepSDKCall()) == null)
	{
		delete hGameConf;
		SetFailState("Failed to end SDKCall \"SDKCall_GetSlot\"!");
		return;
	}

	delete hGameConf;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void EW_OnClientItemWeaponInteract(int iClient, CItem hItem, int iInteractionType)
{
	if ((iInteractionType != EW_WEAPON_INTERACTION_DEATH) &&
		(iInteractionType != EW_WEAPON_INTERACTION_DISCONNECT))
		return;

	if (0 <= SDKCall(SDKCall_GetSlot, hItem.iWeapon) < 2)
		SDKHooks_DropWeapon(iClient, hItem.iWeapon, NULL_VECTOR, NULL_VECTOR); // Using this causes ammo to disapear on the weapon
}
