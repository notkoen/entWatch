//====================================================================================================
//
// Name: [entWatch] Tools
// Author: zaCade & Prometheum
// Description: Handle the tools of [entWatch]
//
//====================================================================================================
// Requires Sourcemod Version: ?
//====================================================================================================
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <entWatch_core>

Handle SDKCall_GetSlot;
Handle SDKCall_OnPickedUp;
Handle SDKCall_BumpWeapon;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Tools",
	author       = "zaCade, Prometheum, koen",
	description  = "Handle the tools of [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("entWatch.phrases");

	RegAdminCmd("sm_etransfer", Command_TransferItem, ADMFLAG_BAN);

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

	// "CBaseCombatWeapon::GetSlot"
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

	// "CBaseCombatWeapon::OnPickedUp"
	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseCombatWeapon::OnPickedUp"))
	{
		delete hGameConf;
		SetFailState("Failed to setup SDKCall \"SDKCall_OnPickedUp\"!");
		return;
	}

	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	if ((SDKCall_OnPickedUp = EndPrepSDKCall()) == null)
	{
		delete hGameConf;
		SetFailState("Failed to end SDKCall \"SDKCall_OnPickedUp\"!");
		return;
	}

	// "CBasePlayer::BumpWeapon"
	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBasePlayer::BumpWeapon"))
	{
		delete hGameConf;
		SetFailState("Failed to setup SDKCall \"SDKCall_BumpWeapon\"!");
		return;
	}

	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	if ((SDKCall_BumpWeapon = EndPrepSDKCall()) == null)
	{
		delete hGameConf;
		SetFailState("Failed to end SDKCall \"SDKCall_BumpWeapon\"!");
		return;
	}

	delete hGameConf;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_TransferItem(int iClient, int args)
{
	if (GetCmdArgs() < 2)
	{
		ReplyToCommand(iClient, "\x04[entWatch] \x01Usage: sm_etransfer <#userid/name/$item> <#userid/name>");
		return Plugin_Handled;
	}

	char sArguments[2][32];
	GetCmdArg(1, sArguments[0], sizeof(sArguments[]));
	GetCmdArg(2, sArguments[1], sizeof(sArguments[]));

	if (strncmp(sArguments[0], "$", 1, false) == 0)
	{
		strcopy(sArguments[0], sizeof(sArguments[]), sArguments[0][1]);

		int reciever;
		if ((reciever = FindTarget(iClient, sArguments[1], true)) == -1)
			return Plugin_Handled;

		char sName[32];
		char sShort[32];
		char sColor[32];

		ArrayList hItems = EW_GetItemsArray();

		bool bTransfered;
		for (int iItemID; iItemID < hItems.Length; iItemID++)
		{
			CItem hItem = hItems.Get(iItemID);

			hItem.hConfig.GetName(sName, sizeof(sName));
			hItem.hConfig.GetShort(sShort, sizeof(sShort));
			hItem.hConfig.GetColor(sColor, sizeof(sColor));

			if (StrContains(sName, sArguments[0], false) != -1 || StrContains(sShort, sArguments[0], false) != -1)
			{
				if (hItem.iWeapon != INVALID_ENT_REFERENCE)
				{
					bool bShowMessages = hItem.hConfig.bShowMessages;

					if (hItem.iClient != INVALID_ENT_REFERENCE)
					{
						SDKHooks_DropWeapon(hItem.iClient, hItem.iWeapon, NULL_VECTOR, NULL_VECTOR);

						char sWeaponClass[32];
						GetEntityClassname(hItem.iWeapon, sWeaponClass, sizeof(sWeaponClass));
						GivePlayerItem(hItem.iClient, sWeaponClass);
					}

					hItem.hConfig.bShowMessages = false;

					FixedEquipPlayerWeapon(reciever, hItem.iWeapon);

					hItem.hConfig.bShowMessages = bShowMessages;
					bTransfered = true;
					break;
				}
			}
		}

		if (!bTransfered)
		{
			ReplyToCommand(iClient, "\x04[entWatch] \x01Error: no transferable items found!");
			return Plugin_Handled;
		}

		PrintToChatAll("\x04[entWatch] \x01%N transfered %s to %N.", iClient, sName, reciever);
		LogAction(iClient, -1, "%L transfered %s to %L.", iClient, sName, reciever);
	}
	else
	{
		int target;
		if ((target = FindTarget(iClient, sArguments[0], true)) == -1)
			return Plugin_Handled;

		int reciever;
		if ((reciever = FindTarget(iClient, sArguments[1], true)) == -1)
			return Plugin_Handled;

		if (GetClientTeam(target) != GetClientTeam(reciever))
		{
			ReplyToCommand(iClient, "\x04[entWatch] \x01Error: teams dont match!");
			return Plugin_Handled;
		}

		ArrayList hItems = EW_GetItemsArray();

		bool bTransfered;
		for (int iItemID; iItemID < hItems.Length; iItemID++)
		{
			CItem hItem = hItems.Get(iItemID);

			if (hItem.iClient != INVALID_ENT_REFERENCE && hItem.iClient == target)
			{
				if (hItem.iWeapon != INVALID_ENT_REFERENCE)
				{
					bool bShowMessages = hItem.hConfig.bShowMessages;

					SDKHooks_DropWeapon(hItem.iClient, hItem.iWeapon, NULL_VECTOR, NULL_VECTOR);

					char sWeaponClass[32];
					GetEntityClassname(hItem.iWeapon, sWeaponClass, sizeof(sWeaponClass));
					GivePlayerItem(hItem.iClient, sWeaponClass);

					hItem.hConfig.bShowMessages = false;

					FixedEquipPlayerWeapon(reciever, hItem.iWeapon);

					hItem.hConfig.bShowMessages = bShowMessages;
					bTransfered = true;
				}
			}
		}

		if (!bTransfered)
		{
			ReplyToCommand(iClient, "\x04[entWatch] \x01Error: target has no transferable items!");
			return Plugin_Handled;
		}

		PrintToChatAll("\x04[entWatch] \x01%N transfered all items from %N to %N.", iClient, target, reciever);
		LogAction(iClient, target, "%L transfered all items from %L to %L.", iClient, target, reciever);
	}

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock void FixedEquipPlayerWeapon(int iClient, int iWeapon)
{
	int iWeaponSlot = SDKCall(SDKCall_GetSlot, iWeapon);
	int WeaponInSlot = GetPlayerWeaponSlot(iClient, iWeaponSlot);
	if (WeaponInSlot != -1)
		SDKHooks_DropWeapon(iClient, WeaponInSlot, NULL_VECTOR, NULL_VECTOR);

	if (SDKCall(SDKCall_BumpWeapon, iClient, iWeapon))
		SDKCall(SDKCall_OnPickedUp, iWeapon, iClient);
}