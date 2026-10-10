"""Validate Lua calls and native member offsets against the local game dump."""
import re


INTERFACES = {
    'GetPalmi': ('Pal.PalUtility', ['WorldContextObject']),
    'GetBaseCampManager': ('Pal.PalUtility', ['WorldContextObject']),
    'GetLocalPlayerGuild': ('Pal.PalGroupUtility', ['WorldContextObject']),
    'GetOwner': ('Engine.ActorComponent', []),
    'K2_GetActorLocation': ('Engine.Actor', []),
    'TryGetModel': ('Pal.PalBaseCampManager', ['BaseCampId', 'OutModel']),
    'GetId': ('Pal.PalBaseCampModel', []),
    'GetGroupIdBelongTo': ('Pal.PalBaseCampModel', []),
    'GetBuildingNum': ('Pal.PalBaseCampModel', []),
    'GetTransform': ('Pal.PalBaseCampModel', []),
    'GetInsideBaseCampModel': ('Pal.PalInsideBaseCampCheckComponent', []),
    'GetMapObjectManager': ('Pal.PalUtility', ['WorldContextObject']),
    'GetLocalPalPlayerController': ('Pal.PalUtility', ['WorldContextObject']),
    'GetItemIDManager': ('Pal.PalUtility', ['WorldContextObject']),
    'GetLocalPlayerState': ('Pal.PalUtility', ['WorldContextObject']),
    'GetLocalRecordData': ('Pal.PalPlayerState', []),
    'GetPlayerUId': ('Pal.PalPlayerController', []),
    'FindConcreteModel': ('Pal.PalMapObjectManager', ['InstanceId']),
    'GetBaseCampIdBelongTo': ('Pal.PalMapObjectConcreteModelBase', []),
    'IsLockedPrivateByNot': ('Pal.PalMapObjectItemChestModel', ['PlayerUId']),
    'GetGuildSecurityModule': ('Pal.PalMapObjectConcreteModelBase', []),
    'GetPasswordLockModule': ('Pal.PalMapObjectConcreteModelBase', []),
    'CheckGuildSecurityAccess': ('Pal.PalMapObjectGuildSecurityModule', ['PlayerUId']),
    'GetLockState': ('Pal.PalMapObjectPasswordLockModule', []),
    'GetItemContainerModule': ('Pal.PalMapObjectConcreteModelBase', []),
    'GetContainer': ('Pal.PalMapObjectItemContainerModule', []),
    'IsEmpty': ('Pal.PalItemSlot', []),
    'IsMaxStack': ('Pal.PalItemSlot', []),
    'GetItemId': ('Pal.PalItemSlot', []),
    'GetSlotId': ('Pal.PalItemSlot', []),
    'GetStaticItemData': ('Pal.PalItemIDManager', ['StaticItemId']),
    'HasDynamicItemClass': ('Pal.PalStaticItemDataBase', []),
    'IsVisible': ('UMG.Widget', []),
    'SetColorAndOpacity': ('UMG.UserWidget', ['InColorAndOpacity']),
    'GetTargetSlot': ('/Game/Pal/Blueprint/UI/Thumbnails/Item/Base/WBP_PalItemSlotButtonBase.WBP_PalItemSlotButtonBase_C', ['TargetSlot']),
    'GetItemSlotButtons': ('/Game/Pal/Blueprint/UI/Inventory/WBP_PalPlayerInventoryScrollList.WBP_PalPlayerInventoryScrollList_C', ['inventoryType','OutSlotButtonArray']),
}
NON_GAME_METHODS = {'get', 'set', 'IsValid', 'IsA', 'GetAddress', 'ForEach', 'ToString', 'Empty', 'gsub', 'match', 'GetArrayNum', 'Add', 'Remove', 'stop', 'arm', 'opened', 'excludeChanged'}


def argument_count(source, start):
    """Count a call's arguments, including nested calls and struct literals."""
    depth, count, quote, escaped, present = 0, 0, None, False, False
    for char in source[start:]:
        if quote:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in "\"'":
            quote, present = char, True
        elif char == ')' and depth == 0:
            return count + int(present)
        elif char in '([{':
            depth += 1
            present = True
        elif char in ')]}':
            depth -= 1
        elif char == ',' and depth == 0:
            count += 1
            present = False
        elif not char.isspace():
            present = True
    raise AssertionError('Unterminated Lua call')


def audit(source, dump_path):
    calls = list(re.finditer(r':(\w+)\s*\(', source))
    for call in calls:
        name = call[1]
        if name in NON_GAME_METHODS:
            continue
        assert name in INTERFACES, f'Unreviewed game method: {name}'
        expected = len(INTERFACES[name][1])
        actual = argument_count(source, call.end())
        assert actual == expected, f'{name}: expected {expected} arguments, found {actual}'
    if not dump_path.exists():
        print('SKIP: game reflection/layout audit requires UE4SS_ObjectDump.txt')
        return
    functions, parameters, offsets = set(), {}, {}
    for line in dump_path.read_text(encoding='utf-8').splitlines():
        fn = re.search(r' Function ((?:/Script/|/Game/)[^ ]+:\w+) ', line)
        if fn:
            functions.add(fn[1].removeprefix('/Script/'))
        param = re.search(r'Property ((?:/Script/|/Game/)[^ ]+:\w+):(\w+) ', line)
        if param and param[2] != 'ReturnValue':
            parameters.setdefault(param[1].removeprefix('/Script/'), []).append(param[2])
        member = re.search(r'Property ((?:/Script/|/Game/)[^ ]+:[^ ]+) \[o: ([0-9A-F]+)\]', line)
        if member:
            offsets[member[1].removeprefix('/Script/')] = int(member[2], 16)
    for name, (owner, expected) in INTERFACES.items():
        key = f'{owner}:{name}'
        assert key in functions, f'Missing UFunction: {key}'
        actual = parameters.get(key, [])
        # Cooked Blueprint dumps also list local variables after the parameters.
        if owner.startswith('/Game/'):
            actual = actual[:len(expected)]
        assert actual == expected, f'Changed parameters: {key}'
    for key, expected in {
        'Pal.PalStaticItemDataBase:TypeB': 0x69,
        'Pal.PalItemContainer:Permission': 0x80,
        'Pal.PalItemContainer:FilterPreference': 0xc8,
        'Pal.PalItemSlot:Permission': 0x160,
        'Pal.PalBaseCampModel:ModuleArray': 0x180,
        'Pal.PalBaseCampModuleItemStorage:ContainerInfos': 0x50,
        'Pal.PalBaseCampItemContainerInfo:OwnerMapObjectConcreteModelInstanceId': 0,
        'Pal.PalPlayerLocalRecordData:Local_ItemQuickMoveExceptionIDList': 0x4d8,
        '/Game/Pal/Blueprint/UI/UserInterface/MainMenu/InventoryEquipment/WBP_InventoryEquipment.WBP_InventoryEquipment_C:UpdateQuickStackableInventorySlot:Editing': 0,
        '/Game/Pal/Blueprint/UI/Thumbnails/Item/Base/WBP_PalItemSlotButtonBase.WBP_PalItemSlotButtonBase_C:GetTargetSlot:TargetSlot': 0,
    }.items():
        assert offsets.get(key) == expected, f'Changed native member offset: {key}'
    print(f'PASS: {len(INTERFACES)} game interface signatures, Lua call arity and native member offsets')
