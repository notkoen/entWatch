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

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Tools",
	author       = "zaCade & Prometheum",
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
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_TransferItem(int iClient, int args)
{
	if (GetCmdArgs() < 2)
	{
		ReplyToCommand(iClient, "\x04[entWatch] \x01Usage: sm_etransfer <#userid/name> <#userid/name>");
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

					EquipPlayerWeapon(reciever, hItem.iWeapon);

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

					EquipPlayerWeapon(reciever, hItem.iWeapon);

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
