#include <sourcemod>
#include <adminmenu>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>

#define PLUGIN_VERSION "0.7.1"

#define ITEM_SPYCICLE 649

new bool:g_bEnabled;
new bool:g_bHealing;
new bool:g_bRandomRound;
new g_iMeleeMode;
new bool:g_bJumper;
new bool:g_bCircuit;
new bool:g_bJetpack;

new Handle:g_hCvarEnabled;
new Handle:g_hCvarMeleeMode;
new Handle:g_hCvarHealing;
new Handle:g_hCvarFlags;
new Handle:g_hCvarFlagsVoting;
new Handle:g_hCvarJumper;
new Handle:g_hCvarCircuit;
new Handle:g_hCvarJetpack;

new Handle:g_hSDKWeaponSwitch;
new Handle:g_hSDKWeaponReset;

new Handle:g_hTopMenu;

new g_iOffsetOwner;
new g_iOffsetDef;
new g_iOffsetState;
new g_iOffsetMelt;

new bool:g_bVoting;

new String:g_strOn[15];
new String:g_strOff[15];

new Handle:g_hForwardMelee;
new Handle:g_hForwardMeleeArena;

public Plugin:myinfo =
{
	name = "Melee",
	author = "linux_lover",
	description = "Toggles melee only mode",
	version = PLUGIN_VERSION,
	url = "http://sourcemod.net"
}

public OnPluginStart()
{
	LookupOffset(g_iOffsetOwner, "CBasePlayer", "m_hActiveWeapon");
	LookupOffset(g_iOffsetDef, "CBaseCombatWeapon", "m_iItemDefinitionIndex");
	LookupOffset(g_iOffsetState, "CTFMinigun", "m_iWeaponState");
	LookupOffset(g_iOffsetMelt, "CTFKnife", "m_flKnifeMeltTimestamp");

	new Handle:hConf = LoadGameConfigFile("sdkhooks.games");
	if(hConf == INVALID_HANDLE)
	{
		SetFailState("Could not read sdkhooks.games gamedata.");
		return;
	}
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "Weapon_Switch");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_hSDKWeaponSwitch = EndPrepSDKCall();
	if(g_hSDKWeaponSwitch == INVALID_HANDLE)
	{
		SetFailState("Could not initialize call for CTFPlayer::Weapon_Switch");
		CloseHandle(hConf);
		return;
	}

	CloseHandle(hConf);
	
	hConf = LoadGameConfigFile("melee");
	if(hConf == INVALID_HANDLE)
	{
		SetFailState("Could not read melee gamedata: gamedata/melee.txt.");
		return;
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CTFWeaponBase::WeaponReset");
	g_hSDKWeaponReset = EndPrepSDKCall();
	if(g_hSDKWeaponReset == INVALID_HANDLE)
	{
		SetFailState("Failed to initalize call: CTFWeaponBase::WeaponReset");
		CloseHandle(hConf);
		return;
	}

	CloseHandle(hConf);
	
	CreateConVar("melee_version", PLUGIN_VERSION, "Plugin Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hCvarEnabled = CreateConVar("melee_enabled", "0", "Enable Melee?");
	g_hCvarHealing = CreateConVar("melee_healing", "0", "1 - Allow healing | 0 - Disallow healing");
	g_hCvarFlags = CreateConVar("melee_flag", "z", "Admin flag for melee only");
	g_hCvarFlagsVoting = CreateConVar("melee_voteflag", "z", "Admin flag fo melee votes");
	g_hCvarMeleeMode = CreateConVar("melee_mode", "0", "0 - Allow non-combat weapons | 1 - Only allow weapon in melee slot");
	g_hCvarJumper = CreateConVar("melee_jumper", "0", "1 - Allow sticky/rocket jumper | 0 - Disallow these weapons");
	g_hCvarCircuit = CreateConVar("melee_circuit", "0", "1 - Allow short circuit | 0 - Disallow short circuit");
	g_hCvarJetpack = CreateConVar("melee_jetpack", "0", "1 - Allow thermal thruster | 0 - Disallow");
	
	RegConsoleCmd("melee", Command_Melee);
	
	HookEvent("teamplay_round_start", Event_RoundStart);
	HookEvent("arena_round_start", Event_RoundStart);
	HookEvent("teamplay_round_win", Event_RoundEnd);
	HookEvent("teamplay_round_stalemate", Event_RoundEnd);
	HookEvent("arena_win_panel", Event_RoundEnd);
	
	HookConVarChange(g_hCvarEnabled, ConVarChange_Enabled);
	HookConVarChange(g_hCvarHealing, ConVarChange_Healing);
	HookConVarChange(g_hCvarMeleeMode, ConVarChange_Mode);
	HookConVarChange(g_hCvarJumper, ConVarChange_Jumper);
	HookConVarChange(g_hCvarCircuit, ConVarChange_Circuit);
	HookConVarChange(g_hCvarJetpack, ConVarChange_Jetpack);
	
	LoadTranslations("melee.phrases");
	LoadTranslations("common.phrases");
	
	Format(g_strOn, sizeof(g_strOn), "%T", "On", LANG_SERVER);
	Format(g_strOff, sizeof(g_strOff), "%T", "Off", LANG_SERVER);
	
	g_hForwardMelee = CreateGlobalForward("OnSetMeleeMode", ET_Ignore, Param_Cell);
	g_hForwardMeleeArena = CreateGlobalForward("OnMeleeArena", ET_Ignore);
}

LookupOffset(&iOffset, const String:strClass[], const String:strProp[])
{
	iOffset = FindSendPropInfo(strClass, strProp);
	if(iOffset <= 0)
	{
		SetFailState("Could not locate offset for %s::%s!", strClass, strProp);
	}
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("SetMeleeMode", Native_SetMeleeMode);
	CreateNative("GetMeleeMode", Native_GetMeleeMode);
	
	RegPluginLibrary("melee");
	
	return APLRes_Success;
}

public OnPluginEnd()
{
	SetMeleeMode(false, false);
}

public OnLibraryRemoved(const String:name[])
{
	if(strcmp(name, "adminmenu") == 0)
	{
		g_hTopMenu = INVALID_HANDLE;
	}
}

public OnConfigsExecuted()
{
	g_bHealing = GetConVarBool(g_hCvarHealing);
	g_iMeleeMode = GetConVarInt(g_hCvarMeleeMode);
	g_bJumper = GetConVarBool(g_hCvarJumper);
	g_bCircuit = GetConVarBool(g_hCvarCircuit);
	g_bJetpack = GetConVarBool(g_hCvarJetpack);
	
	new Handle:hTopMenu;
	if(LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(hTopMenu);
	}
}

public OnMapStart()
{
	SetMeleeMode(false, false);
	g_bRandomRound = false;
	g_bVoting = false;
}

public Action:Command_Melee(client, args)
{
	if(client > 0)
	{
		decl String:strFlags[10];
		GetConVarString(g_hCvarFlags, strFlags, sizeof(strFlags));
		if(!CheckAdminFlagsByString(client, strFlags))
		{
			PrintToChat(client, "\x01[SM] You are not allowed to do that.");
			return Plugin_Handled;
		}
	}
	
	// A melee vote is currently taking place
	if(IsVoteInProgress() && g_bVoting)
	{
		CancelVote();
		PrintToChatAll("\x04 %T", "Vote_Canceled", LANG_SERVER);
	}
	
	// Toggle
	if(args == 0)
	{
		if(g_bEnabled == true)
		{
			SetMeleeMode(false);
		}else{
			SetMeleeMode(true);
		}
	}else{
		new String:strArg1[5];
		GetCmdArg(1, strArg1, sizeof(strArg1));
		
		if(StringToInt(strArg1) >= 1)
		{
			SetMeleeMode(true);
		}else{
			SetMeleeMode(false);
		}
	}
	
	return Plugin_Handled;
}

public ConVarChange_Enabled(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bEnabled = bool:StringToInt(newValue);
}

public ConVarChange_Healing(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bHealing = bool:StringToInt(newValue);
}

public ConVarChange_Mode(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_iMeleeMode = StringToInt(newValue);
}

public ConVarChange_Jumper(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bJumper = bool:StringToInt(newValue);
}

public ConVarChange_Circuit(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bCircuit = bool:StringToInt(newValue);
}

public ConVarChange_Jetpack(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_bJetpack = bool:StringToInt(newValue);
}

SetMeleeMode(bool:bEnabled, bool:bVerbose=true)
{
	if(bEnabled)
	{
		g_bEnabled = true;
	}else{
		g_bEnabled = false;
	}
	
	SetSentryDisable(g_bEnabled);
	SetBotMelee(g_bEnabled);
	
	Call_StartForward(g_hForwardMelee);
	Call_PushCell(bEnabled);
	Call_Finish();
	
	if(bVerbose) PrintToChatAll("\x04 %T", "Melee_Action", LANG_SERVER, 0x01, g_bEnabled ? g_strOn : g_strOff);
}

public OnGameFrame()
{
	if(g_bEnabled)
	{
		decl String:strClass[32];
		for(new i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i) && IsPlayerAlive(i))
			{
				new iWeapon = GetPlayerWeaponSlot(i, TFWeaponSlot_Melee);
				new iActive = GetActiveWeapon(i);
				
				if(iWeapon > MaxClients && iActive > MaxClients && iWeapon != iActive)
				{
					new iDefMelee = GetItemDefinition(iWeapon);
					new iDefActive = GetItemDefinition(iActive);
					GetEdictClassname(iActive, strClass, sizeof(strClass));

					if(iDefMelee == ITEM_SPYCICLE && GetKnifeMeltTimestamp(iWeapon) != 0.0)
					{
						SetKnifeMeltTimestamp(iWeapon, 0.0);
					}

					if(strcmp(strClass, "tf_weapon_minigun") == 0)
					{
						ResetMinigun(iActive, 0);
						TF2_RemoveCondition(i, TFCond_Slowed);
					}

					if(g_iMeleeMode) // Strict melee mode
					{
						if(!CanUseWeaponInStrict(iDefActive))
						{
							SDK_ResetWeapon(iActive);
							SetActiveWeapon(i, iWeapon);
						}
					}else{
						if(!CanUseWeapon(iDefActive))
						{
							SDK_ResetWeapon(iActive);
							SetActiveWeapon(i, iWeapon);
						}
					}
				}
			}
		}
	}
}

bool CanUseWeaponInStrict(int itemDef)
{
	switch(itemDef)
	{
		case 1155: return true; // Passtime Gun.
	}

	return false;
}

bool CanUseWeapon(int itemDef)
{
	switch(itemDef)
	{
		case 735,736,810,831,933,1080,1102: return true; // Spy Sapper / Upgradable Sapper / Recorder / Recorder Promo / Ap-Sap / Festive Sapper / Snack Attack
		case 25,26,28,737: return true; // Engineer's Build & Destroy PDAs / Builder / Upgradable Build PDA
		case 140,1086: return true; // Wrangler / Festive Wrangler
		case 58,1083,1105: return true; // Jarate / Festive Jarate / Self-Aware Beauty Mark
		case 42,159,311,433,863,1002,1190: return true; // Sandvich / Chocolate Bar / Buffalo Steak / Fishcake / Robo-Sandvich / Festive Sandvich / Second Banana
		case 46,163,222,1121,1145: return true; // Bonk / Crit-a-Cola / Mad Milk / Mutated Milk / Festive Bonk
		case 27: return true; // Spy Disguise PDA
		case 129,226,354,1001: return true; // The Buff Banner / The Battalion's Backup / The Concheror / Festive Buff Banner
		case 29,35,411,211,663: return g_bHealing; // Medigun / Kritzcrieg / The Quick-Fix / Strange Medigun / Festive Medigun
		case 237,265: return g_bJumper; // Rocket/Sticky Jumper
		case 528: return g_bCircuit; // Short Circuit
		case 1069,1070,5605: return true; // Spell Books
		case 1152: return true; // Grappling Hook
		case 1179: return g_bJetpack; // Thermal Thruster
		case 1180: return true; // Gas Passer
	}

	if(CanUseWeaponInStrict(itemDef)) return true;
	
	return false;
}

GetItemDefinition(weapon)
{
	return GetEntData(weapon, g_iOffsetDef);
}

GetActiveWeapon(client)
{
	return GetEntDataEnt2(client, g_iOffsetOwner);
}

SetActiveWeapon(client, iWeapon)
{
	SDKCall(g_hSDKWeaponSwitch, client, iWeapon, 0);
}

Float:GetKnifeMeltTimestamp(iKnife)
{
	return GetEntDataFloat(iKnife, g_iOffsetMelt);
}

SetKnifeMeltTimestamp(iKnife, Float:flAmount)
{
	SetEntDataFloat(iKnife, g_iOffsetMelt, flAmount);
}

SetSentryDisable(bool:bEnabled)
{
	new Handle:hCvar = FindConVar("tf_sentrygun_notarget");
	SetConVarBool(hCvar, bEnabled);
	CloseHandle(hCvar);
}

SetBotMelee(bool:bEnabled)
{
	new Handle:hCvar = FindConVar("tf_bot_melee_only");
	SetConVarBool(hCvar, bEnabled);
	CloseHandle(hCvar);
}

stock bool:CheckAdminFlagsByString(client, const String:strFlagString[])
{
	if(strlen(strFlagString))
	{
		new iUserFlags = GetUserFlagBits(client);
		return bool:(iUserFlags & ADMFLAG_ROOT || iUserFlags & ReadFlagString(strFlagString));
	}
	
	return true;
}

public OnAdminMenuReady(Handle:hTopMenu)
{	
	if(hTopMenu == g_hTopMenu)
	{
		return;
	}
	
	new String:strFlags[5];
	GetConVarString(g_hCvarFlags, strFlags, sizeof(strFlags));
	new iFlags = ADMFLAG_ROOT;
	if(!StrEqual(strFlags, ""))
	{
		iFlags = ReadFlagString(strFlags);
	}
	
	g_hTopMenu = hTopMenu;
	
	new TopMenuObject:TopMenuServerCommands = FindTopMenuCategory(g_hTopMenu, ADMINMENU_SERVERCOMMANDS);
	if(TopMenuServerCommands != INVALID_TOPMENUOBJECT)
	{
		AddToTopMenu(g_hTopMenu, "melee", TopMenuObject_Item, AdminMenu_Melee, TopMenuServerCommands, "melee", iFlags);
	}
	
	GetConVarString(g_hCvarFlagsVoting, strFlags, sizeof(strFlags));
	iFlags = ADMFLAG_ROOT;
	if(!StrEqual(strFlags, ""))
	{
		iFlags = ReadFlagString(strFlags);
	}
}

public AdminMenu_Melee(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "Toggle melee: %s", g_bEnabled ? g_strOff : g_strOn);
	}else if(action == TopMenuAction_SelectOption)
	{
		Command_Melee(param, 0);
		DisplayTopMenu(g_hTopMenu, param, TopMenuPosition_LastCategory);
	}
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_bEnabled = GetConVarBool(g_hCvarEnabled);

	if(g_bEnabled)
	{
		g_bRandomRound = true;
		SetMeleeMode(true, false);
		
		Call_StartForward(g_hForwardMeleeArena);
		Call_Finish();
		
		PrintToChatAll("\x04 %T", "Arena_Melee", LANG_SERVER, 0x01, 0x04);
	}
	
	return Plugin_Continue;
}

public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(g_bEnabled && g_bRandomRound)
	{
		g_bRandomRound = false;
		SetMeleeMode(false);
	}
	
	return Plugin_Continue;
}

public Native_SetMeleeMode(Handle:plugin, numParams)
{
	new bool:bEnabled = bool:GetNativeCell(1);
	new bool:bVerbose = bool:GetNativeCell(2);
	
	SetMeleeMode(bEnabled, bVerbose);
}

public Native_GetMeleeMode(Handle:plugin, numParams)
{
	return _:g_bEnabled;
}

SDK_ResetWeapon(weapon)
{
	if(g_hSDKWeaponReset != INVALID_HANDLE)
	{
#if defined DEBUG
		PrintToServer("(SDK_ResetWeapon) Calling on weapon %d..", weapon);
#endif
		SDKCall(g_hSDKWeaponReset, weapon);
	}
}

ResetMinigun(weapon, iState)
{
    SetEntData(weapon, g_iOffsetState, iState, 4, false);
}
