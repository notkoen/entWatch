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

/* CONVARS */
ConVar g_hCVar_UseHEXColors;
ConVar g_hCVar_ColorConfig;
ConVar g_hCVar_MessageMode;

/* STRUCTS */
enum struct ColorStruct
{
	char sTag[8];           // String: Hex color of entwatch tag
	char sName[8];          // String: Hex color of player name
	char sAuthID[8];        // String: Hex color of player steam ID
	char sActivate[8];      // String: Hex color of item use message
	char sPickup[8];        // String: Hex color of item pickup message
	char sDrop[8];          // String: Hex color of item drop message
	char sDeath[8];         // String: Hex color of player death message
	char sDisconnect[8];    // String: Hex color of player disconnect message
	char sWarning[8];       // String: Hex color of warning message

	void Reset()
	{
		this.sTag           = "E11E64";
		this.sName          = "F0F0F0";
		this.sAuthID        = "B4B4B4";
		this.sActivate      = "64AFE1";
		this.sPickup        = "AFE164";
		this.sDrop          = "E164AF";
		this.sDeath         = "E1AF64";
		this.sDisconnect    = "E1AF64";
		this.sWarning       = "E1AF64";
	}
}

ColorStruct g_colorStruct;

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

	g_hCVar_MessageMode = CreateConVar("sm_emessages_mode", "1", "Entwatch message recipient mode (1 = All, 2 = Team Only + Admin, 3 = Team Only)", FCVAR_NONE, true, 1.0, true, 3.0);
	g_hCVar_UseHEXColors = CreateConVar("sm_emessages_usehex", "1", "Allow HEX color codes to be used.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCVar_ColorConfig = CreateConVar("sm_emessages_config", "classic", "Name of entWatch-message color config file");
	g_hCVar_ColorConfig.AddChangeHook(OnConVarChange);

	LoadColors();
	AutoExecConfig();
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_hCVar_ColorConfig)
		LoadColors();
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock void LoadColors()
{
	g_colorStruct.Reset();

	char sConfig[32], sFilePath[PLATFORM_MAX_PATH];
	g_hCVar_ColorConfig.GetString(sConfig, sizeof(sConfig));
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/entwatch/colors/%s.cfg", sConfig);

	KeyValues kv = new KeyValues("colors");
	if (!kv.ImportFromFile(sFilePath))
	{
		delete kv;
		LogError("[entWatch-messages] Failed to load color config. Falling back on default colors.");
		return;
	}

	kv.GetString("color_tag",           g_colorStruct.sTag,         sizeof(g_colorStruct.sTag),         g_colorStruct.sTag);
	kv.GetString("color_name",          g_colorStruct.sName,        sizeof(g_colorStruct.sName),        g_colorStruct.sName);
	kv.GetString("color_steamid",       g_colorStruct.sAuthID,      sizeof(g_colorStruct.sAuthID),      g_colorStruct.sAuthID);
	kv.GetString("color_use",           g_colorStruct.sActivate,    sizeof(g_colorStruct.sActivate),    g_colorStruct.sActivate);
	kv.GetString("color_pickup",        g_colorStruct.sPickup,      sizeof(g_colorStruct.sPickup),      g_colorStruct.sPickup);
	kv.GetString("color_drop",          g_colorStruct.sDrop,        sizeof(g_colorStruct.sDrop),        g_colorStruct.sDrop);
	kv.GetString("color_death",         g_colorStruct.sDeath,       sizeof(g_colorStruct.sDeath),       g_colorStruct.sDeath);
	kv.GetString("color_disconnect",    g_colorStruct.sDisconnect,  sizeof(g_colorStruct.sDisconnect),  g_colorStruct.sDisconnect);
	kv.GetString("color_warning",       g_colorStruct.sWarning,     sizeof(g_colorStruct.sWarning),     g_colorStruct.sWarning);

	delete kv;
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

	char sTranslation[32], sColor[8];
	switch (iInteractionType)
	{
		case EW_WEAPON_INTERACTION_DROP:
		{
			Format(sTranslation, sizeof(sTranslation), "Item Drop");
			Format(sColor, sizeof(sColor), g_colorStruct.sDrop);
		}
		case EW_WEAPON_INTERACTION_DEATH:
		{
			Format(sTranslation, sizeof(sTranslation), "Item Death");
			Format(sColor, sizeof(sColor), g_colorStruct.sDeath);
		}
		case EW_WEAPON_INTERACTION_PICKUP:
		{
			Format(sTranslation, sizeof(sTranslation), "Item Pickup");
			Format(sColor, sizeof(sColor), g_colorStruct.sPickup);
		}
		case EW_WEAPON_INTERACTION_DISCONNECT:
		{
			Format(sTranslation, sizeof(sTranslation), "Item Disconnect");
			Format(sColor, sizeof(sColor), g_colorStruct.sDisconnect);
		}
	}

	char sItemName[32];
	hItem.hConfig.GetName(sItemName, sizeof(sItemName));

	if (g_hCVar_UseHEXColors.BoolValue)
	{
		char sItemColor[8];
		hItem.hConfig.GetColor(sItemColor, sizeof(sItemColor));

		EW_PrintChatMessage(iClient, "\x07%6s[entWatch] \x07%6s%s \x01(\x07%6s%s\x01) \x07%6s%t \x07%6s%s", g_colorStruct.sTag, g_colorStruct.sName, sClientName, g_colorStruct.sAuthID, sClientAuth, sColor, sTranslation, sItemColor, sItemName);
	}
	else
	{
		// CSGO Colors.
		// x02 = Zombies
		// x08 = Neutral
		// x0C = Humans
		// CSGO: Requires a character before colors will work, so add a space.

		char sTeamColor[8];
		int iTeam = GetClientTeam(iClient);

		switch (iTeam)
		{
			case 2:
				strcopy(sTeamColor, sizeof(sTeamColor), "\x02");
			case 3:
				strcopy(sTeamColor, sizeof(sTeamColor), "\x0C");
			default:
				strcopy(sTeamColor, sizeof(sTeamColor), "\x08");
		}

		EW_PrintChatMessage(iClient, " \x04[entWatch] \x01%s (\x05%s\x01) %t %s%s", sClientName, sClientAuth, sTranslation, sTeamColor, sItemName);
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

	char sItemName[32], sButtonName[32];
	hItemButton.hItem.hConfig.GetName(sItemName, sizeof(sItemName));
	hItemButton.hConfigButton.GetName(sButtonName, sizeof(sButtonName));

	if (g_hCVar_UseHEXColors.BoolValue)
	{
		char sItemColor[8];
		hItemButton.hItem.hConfig.GetColor(sItemColor, sizeof(sItemColor));

		if (strlen(sButtonName) != 0)
			EW_PrintChatMessage(iClient, "\x07%6s[entWatch] \x07%6s%s \x01(\x07%6s%s\x01) \x07%6s%t \x07%6s%s \x01(\x07%6s%s\x01)", g_colorStruct.sTag, g_colorStruct.sName, sClientName, g_colorStruct.sAuthID, sClientAuth, g_colorStruct.sActivate, "Item Activate", sItemColor, sItemName, sItemColor, sButtonName);
		else
			EW_PrintChatMessage(iClient, "\x07%6s[entWatch] \x07%6s%s \x01(\x07%6s%s\x01) \x07%6s%t \x07%6s%s", g_colorStruct.sTag, g_colorStruct.sName, sClientName, g_colorStruct.sAuthID, sClientAuth, g_colorStruct.sActivate, "Item Activate", sItemColor, sItemName);
	}
	else
	{
		char sTeamColor[8];
		int iTeam = GetClientTeam(iClient);

		switch (iTeam)
		{
			case 2:
				strcopy(sTeamColor, sizeof(sTeamColor), "\x02");
			case 3:
				strcopy(sTeamColor, sizeof(sTeamColor), "\x0C");
			default:
				strcopy(sTeamColor, sizeof(sTeamColor), "\x08");
		}

		if (strlen(sButtonName) != 0)
			EW_PrintChatMessage(iClient, " \x04[entWatch] \x01%s (\x05%s\x01) %t %s%s (%s)", sClientName, sClientAuth, "Item Activate", sTeamColor, sItemName, sButtonName);
		else
			EW_PrintChatMessage(iClient, " \x04[entWatch] \x01%s (\x05%s\x01) %t %s%s", sClientName, sClientAuth, "Item Activate", sTeamColor, sItemName);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock void EW_PrintChatMessage(int iClient, const char[] sMessage, any ...)
{
	char sBuffer[255];
	VFormat(sBuffer, sizeof(sBuffer), sMessage, 3);

	int iTeam = GetClientTeam(iClient);

	switch (g_hCVar_MessageMode.IntValue)
	{
		case 2:
		{
			for (int i; i <= MaxClients; i++)
			{
				if (!IsClientInGame(i))
					continue;

				if (GetClientTeam(i) == iTeam || CheckCommandAccess(i, "", ADMFLAG_GENERIC))
					PrintToChat(i, "%s", sBuffer);
			}
		}
		case 3:
		{
			for (int i; i <= MaxClients; i++)
			{
				if (!IsClientInGame(i))
					continue;

				if (GetClientTeam(i) == iTeam)
					PrintToChat(i, "%s", sBuffer);
			}
		}
		default: PrintToChatAll("%s", sBuffer);
	}
}