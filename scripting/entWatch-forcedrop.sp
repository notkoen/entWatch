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

#include <sourcemod>
#include <sdkhooks>
#include <entWatch_core>

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Forcedrop",
	author       = "zaCade & Prometheum",
	description  = "Handle the forced dropping of weapons of [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{

}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void EW_OnClientItemWeaponInteract(int iClient, CItem hItem, int iInteractionType)
{
	if ((iInteractionType != EW_WEAPON_INTERACTION_DEATH) &&
		(iInteractionType != EW_WEAPON_INTERACTION_DISCONNECT))
		return;

	// Check if its not a knife. (Slot 3)

	//SDKHooks_DropWeapon(iClient, hItem.iWeapon, NULL_VECTOR, NULL_VECTOR, false); -- Using this causes ammo to disapear on the weapon.
}
