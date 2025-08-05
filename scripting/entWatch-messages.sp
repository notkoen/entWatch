//====================================================================================================
//
// Name: [entWatch] Messages
// Author: zaCade & Prometheum
// Description: Handle the chat messages of [entWatch]
//
//====================================================================================================
// Requires Sourcemod Version: ?
//====================================================================================================
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <entWatch_core>

/* CONVARS *//*
ConVar g_hCVar_UseHEXColors = null;

ConVar g_hCVar_Color_Tag = null;
ConVar g_hCVar_Color_Names = null;
ConVar g_hCVar_Color_AuthID = null;
ConVar g_hCVar_Color_Activate = null;
ConVar g_hCVar_Color_Pickup = null;
ConVar g_hCVar_Color_Drop = null;
ConVar g_hCVar_Color_Death = null;
ConVar g_hCVar_Color_Disconnect = null;
ConVar g_hCVar_Color_Warning = null;*/

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Messages",
	author       = "zaCade & Prometheum",
	description  = "Handle the chat messages of [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadTranslations("entWatch.phrases");
/*
	g_hCVar_UseHEXColors = CreateConVar("sm_emessages_usehex", "1", "Allow HEX color codes to be used.", FCVAR_NONE, true, 0.0, true, 1.0);

	g_hCVar_Color_Tag        = CreateConVar("sm_emessage_color_tag",        "E11E64", "The HEX color code for the tags.",                FCVAR_NONE);
	g_hCVar_Color_Names      = CreateConVar("sm_emessage_color_names",      "F0F0F0", "The HEX color code for names.",                   FCVAR_NONE);
	g_hCVar_Color_AuthID     = CreateConVar("sm_emessage_color_authid",     "B4B4B4", "The HEX color code for the authids.",             FCVAR_NONE);
	g_hCVar_Color_Activate   = CreateConVar("sm_emessage_color_activate",   "64AFE1", "The HEX color code for the activation messages.", FCVAR_NONE);
	g_hCVar_Color_Pickup     = CreateConVar("sm_emessage_color_pickup",     "AFE164", "The HEX color code for the pickup messages.",     FCVAR_NONE);
	g_hCVar_Color_Drop       = CreateConVar("sm_emessage_color_drop",       "E164AF", "The HEX color code for the drop messages.",       FCVAR_NONE);
	g_hCVar_Color_Death      = CreateConVar("sm_emessage_color_death",      "E1AF64", "The HEX color code for the death messages.",      FCVAR_NONE);
	g_hCVar_Color_Disconnect = CreateConVar("sm_emessage_color_disconnect", "E1AF64", "The HEX color code for the disconnect messages.", FCVAR_NONE);
	g_hCVar_Color_Warning    = CreateConVar("sm_emessage_color_warning",    "E16464", "The HEX color code for the warning messages.",    FCVAR_NONE);

	AutoExecConfig();*/
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void EW_OnClientItemWeaponInteract(int iClient, CItem hItem, int iInteractionType)
{
	if (!hItem.hConfig.bShowMessages)
		return;

	SetGlobalTransTarget(LANG_SERVER);

	char sClientName[32];
	GetClientName(iClient, sClientName, sizeof(sClientName));

	char sClientAuth[32];
	GetClientAuthId(iClient, AuthId_Steam2, sClientAuth, sizeof(sClientAuth));

	char sTranslation[32];
	switch (iInteractionType)
	{
		case (EW_WEAPON_INTERACTION_DROP):
			Format(sTranslation, sizeof(sTranslation), "Item Drop");

		case (EW_WEAPON_INTERACTION_DEATH):
			Format(sTranslation, sizeof(sTranslation), "Item Death");

		case (EW_WEAPON_INTERACTION_PICKUP):
			Format(sTranslation, sizeof(sTranslation), "Item Pickup");

		case (EW_WEAPON_INTERACTION_DISCONNECT):
			Format(sTranslation, sizeof(sTranslation), "Item Disconnect");
	}

	char sItemName[32];
	hItem.hConfig.GetName(sItemName, sizeof(sItemName));

	if (IsSource2009())
	{
		char sItemColor[8];
		hItem.hConfig.GetColor(sItemColor, sizeof(sItemColor));

		PrintToChatAll("\x04[entWatch] \x01%s (\x05%s\x01) %t \x07%6s%s", sClientName, sClientAuth, sTranslation, sItemColor, sItemName);
	}
	else
	{
		//CSGO Colors.
		//x02 = Zombies
		//x08 = Neutral
		//x0C = Humans

		char sTeamColor[8];
		switch (GetClientTeam(iClient))
		{
			case (2):
				strcopy(sTeamColor, sizeof(sTeamColor), "\x02");
			case (3):
				strcopy(sTeamColor, sizeof(sTeamColor), "\x0C");
			default:
				strcopy(sTeamColor, sizeof(sTeamColor), "\x08");
		}

		// CSGO: Requires a character before colors will work, so add a space.
		PrintToChatAll(" \x04[entWatch] \x01%s (\x05%s\x01) %t %s%s", sClientName, sClientAuth, sTranslation, sTeamColor, sItemName);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void EW_OnClientItemButtonInteract(int iClient, CItemButton hItemButton)
{
	if (!hItemButton.hConfigButton.bShowActivate)
		return;

	SetGlobalTransTarget(LANG_SERVER);

	char sClientName[32];
	GetClientName(iClient, sClientName, sizeof(sClientName));

	char sClientAuth[32];
	GetClientAuthId(iClient, AuthId_Steam2, sClientAuth, sizeof(sClientAuth));

	char sItemName[32];
	hItemButton.hItem.hConfig.GetName(sItemName, sizeof(sItemName));

	if (IsSource2009())
	{
		char sItemColor[8];
		hItemButton.hItem.hConfig.GetColor(sItemColor, sizeof(sItemColor));

		PrintToChatAll("\x04[entWatch] \x01%s (\x05%s\x01) %t \x07%6s%s", sClientName, sClientAuth, "Item Activate", sItemColor, sItemName);
	}
	else
	{
		char sTeamColor[8];
		switch (GetClientTeam(iClient))
		{
			case (2):
				strcopy(sTeamColor, sizeof(sTeamColor), "\x02");
			case (3):
				strcopy(sTeamColor, sizeof(sTeamColor), "\x0C");
			default:
				strcopy(sTeamColor, sizeof(sTeamColor), "\x08");
		}

		// CSGO: Requires a character before colors will work, so add a space.
		PrintToChatAll(" \x04[entWatch] \x01%s (\x05%s\x01) %t %s%s", sClientName, sClientAuth, "Item Activate", sTeamColor, sItemName);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool IsSource2009()
{
	static bool bHasChecked = false;
	static bool bIsSource2009 = false;

	if (!bHasChecked)
	{
		bHasChecked = true;
		bIsSource2009 = (GetEngineVersion() == Engine_CSS || GetEngineVersion() == Engine_HL2DM || GetEngineVersion() == Engine_DODS || GetEngineVersion() == Engine_TF2);
	}

	return bIsSource2009;
}
