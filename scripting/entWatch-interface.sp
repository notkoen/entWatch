//====================================================================================================
//
// Name: [entWatch] Interface
// Author: zaCade, Prometheum, koen
// Description: Handle the interface of [entWatch]
//
//====================================================================================================
// Requires Sourcemod Version: 1.10.0.6531 or above
//====================================================================================================
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs_stocks>
#include <entWatch_core>

/* BOOLEANS */
bool g_bInterfaceHidden[MAXPLAYERS+1];

/* CONVARS */
ConVar g_hCVar_InterfaceMode;

/* COOKIES */
Cookie_Stocks g_hCookie_InterfaceHidden;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Interface",
	author       = "zaCade, Prometheum, koen",
	description  = "Handle the interface of [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadTranslations("entWatch.phrases");

	g_hCVar_InterfaceMode = CreateConVar("sm_einterface_mode", "3", "Entwatch interface display mode (1 = All items, 2 = Admin all items/Team items only, 3 = Team items only", FCVAR_NONE, true, 1.0, true, 3.0);

	g_hCookie_InterfaceHidden = new Cookie_Stocks("EW_InterfaceHidden", "", CookieAccess_Private);

	RegConsoleCmd("sm_hud", Command_ToggleHUD);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnMapStart()
{
	CreateTimer(1.0, OnDisplayHUD, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientCookiesCached(int iClient)
{
	g_bInterfaceHidden[iClient] = g_hCookie_InterfaceHidden.GetBool(iClient);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public void OnClientDisconnect(int iClient)
{
	g_bInterfaceHidden[iClient] = false;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action Command_ToggleHUD(int iClient, int iArgs)
{
	g_bInterfaceHidden[iClient] = !g_bInterfaceHidden[iClient];

	g_hCookie_InterfaceHidden.SetBool(iClient, g_bInterfaceHidden[iClient]);
	ReplyToCommand(iClient, "\x04[entWatch] \x01You will now %ssee the HUD.", g_bInterfaceHidden[iClient] ? "no longer " : "");
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool FormatButtonCooldown(char[] sBuffer, const int iMaxLength, CItemButton hItemButton)
{
	switch (hItemButton.hConfigButton.iMode)
	{
		case EW_BUTTON_MODE_COOLDOWN:
		{
			if (hItemButton.flReadyTime > GetGameTime())
			{
				Format(sBuffer, iMaxLength, "%d", RoundToNearest(hItemButton.flReadyTime - GetGameTime()));
				return true;
			}
			else
			{
				Format(sBuffer, iMaxLength, "R");
				return true;
			}
		}
		case EW_BUTTON_MODE_MAXUSES:
		{
			if (hItemButton.iCurrentUses >= hItemButton.hConfigButton.iMaxUses)
			{
				Format(sBuffer, iMaxLength, "E");
				return true;
			}
			else if (hItemButton.flReadyTime > GetGameTime())
			{
				Format(sBuffer, iMaxLength, "%d", RoundToNearest(hItemButton.flReadyTime - GetGameTime()));
				return true;
			}
			else
			{
				Format(sBuffer, iMaxLength, "%d/%d", hItemButton.iCurrentUses, hItemButton.hConfigButton.iMaxUses);
				return true;
			}
		}
		case EW_BUTTON_MODE_COOLDOWN_CHARGES:
		{
			if (hItemButton.flReadyTime > GetGameTime())
			{
				Format(sBuffer, iMaxLength, "%d", RoundToNearest(hItemButton.flReadyTime - GetGameTime()));
				return true;
			}
			else
			{
				Format(sBuffer, iMaxLength, "%d/%d", hItemButton.iCurrentUses, hItemButton.hConfigButton.iMaxUses);
				return true;
			}
		}
		case EW_BUTTON_MODE_COUNTERVALUE:
		{
			if (hItemButton.iCurrentUses <= 0)
			{
				Format(sBuffer, iMaxLength, "E");
				return true;
			}
			else
			{
				Format(sBuffer, iMaxLength, "%d/%d", hItemButton.iCurrentUses, hItemButton.hConfigButton.iMaxUses);
				return true;
			}
		}
	}

	return false;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock bool FormatItemCooldowns(char[] sBuffer, const int iMaxLength, CItem hItem)
{
	bool bHasCooldown;

	for (int iItemButtonID; iItemButtonID < hItem.hButtons.Length; iItemButtonID++)
	{
		CItemButton hItemButton = hItem.hButtons.Get(iItemButtonID);

		if (!hItemButton.hConfigButton.bShowCooldown)
			continue;

		char sCooldown[8];

		if (!FormatButtonCooldown(sCooldown, sizeof(sCooldown), hItemButton))
			continue;

		if (!bHasCooldown)
		{
			bHasCooldown = true;

			StrCat(sBuffer, iMaxLength, sCooldown);
		}
		else
		{
			StrCat(sBuffer, iMaxLength, "|");
			StrCat(sBuffer, iMaxLength, sCooldown);
		}
	}

	return bHasCooldown;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock Action OnDisplayHUD(Handle hTimer)
{
	int iHUDPages[3];
	char sHUDPages[3][8][255];

	ArrayList hItems = EW_GetItemsArray();

	for (int iItemID; iItemID < hItems.Length; iItemID++)
	{
		CItem hItem = hItems.Get(iItemID);

		if (!hItem.hConfig.bShowInterface || hItem.iClient == INVALID_ENT_REFERENCE)
			continue;

		char sShort[16];
		hItem.hConfig.GetShort(sShort, sizeof(sShort));

		char sCooldowns[16];
		bool bCooldowns = FormatItemCooldowns(sCooldowns, sizeof(sCooldowns), hItem);

		char sLine[64];

		if (bCooldowns)
			Format(sLine, sizeof(sLine), "%s [%s]: %N", sShort, sCooldowns, hItem.iClient);
		else
			Format(sLine, sizeof(sLine), "%s [N/A]: %N", sShort, hItem.iClient);

		switch (GetClientTeam(hItem.iClient))
		{
			case 2:
			{
				if (strlen(sHUDPages[1][iHUDPages[1]]) + strlen(sLine) + 2 >= sizeof(sHUDPages[][]))
					iHUDPages[1]++;

				StrCat(sHUDPages[1][iHUDPages[1]], sizeof(sHUDPages[][]), sLine);
				StrCat(sHUDPages[1][iHUDPages[1]], sizeof(sHUDPages[][]), "\n");
			}
			case 3:
			{
				if (strlen(sHUDPages[2][iHUDPages[2]]) + strlen(sLine) + 2 >= sizeof(sHUDPages[][]))
					iHUDPages[2]++;

				StrCat(sHUDPages[2][iHUDPages[2]], sizeof(sHUDPages[][]), sLine);
				StrCat(sHUDPages[2][iHUDPages[2]], sizeof(sHUDPages[][]), "\n");
			}
		}

		if (strlen(sHUDPages[0][iHUDPages[0]]) + strlen(sLine) + 2 >= sizeof(sHUDPages[][]))
			iHUDPages[0]++;

		StrCat(sHUDPages[0][iHUDPages[0]], sizeof(sHUDPages[][]), sLine);
		StrCat(sHUDPages[0][iHUDPages[0]], sizeof(sHUDPages[][]), "\n");
	}

	static int iPageInterval;
	static int iPageCurrent[3];

	if (iPageInterval >= 5)
	{
		for (int iPageID; iPageID < 3; iPageID++)
		{
			if (iPageCurrent[iPageID] >= iHUDPages[iPageID])
				iPageCurrent[iPageID] = 0;
			else
				iPageCurrent[iPageID]++;
		}

		iPageInterval = 0;
	}
	else
		iPageInterval++;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || (IsFakeClient(iClient) && !IsClientSourceTV(iClient)) || g_bInterfaceHidden[iClient])
			continue;

		int iPagePanel;

		switch (g_hCVar_InterfaceMode.IntValue)
		{
			case 1: iPagePanel = 0;
			case 2:
			{
				if (CheckCommandAccess(iClient, "", ADMFLAG_BAN))
					iPagePanel = 0;
				else
				{
					switch (GetClientTeam(iClient))
					{
						case 2: iPagePanel = 1;
						case 3: iPagePanel = 2;
					}
				}
			}
			case 3:
			{
				switch (GetClientTeam(iClient))
				{
					case 2: iPagePanel = 1;
					case 3: iPagePanel = 2;
				}
			}
		}

		if (sHUDPages[iPagePanel][iPageCurrent[iPagePanel]][0])
		{

			Handle hMessage = StartMessageOne("KeyHintText", iClient);

			if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
				PbAddString(hMessage, "hints", sHUDPages[iPagePanel][iPageCurrent[iPagePanel]]);
			else
			{
				// Byte: message amount.
				// String: message string.
				BfWriteByte(hMessage, 1);
				BfWriteString(hMessage, sHUDPages[iPagePanel][iPageCurrent[iPagePanel]]);
			}

			EndMessage();
		}
	}

	return Plugin_Continue;
}