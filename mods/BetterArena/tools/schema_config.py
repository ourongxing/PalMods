"""Pure PalSchema patch generation, using the verified 1.0.5 Arena base values."""
import copy


def patches(base, multiplier):
    if type(multiplier) is not int or not 1 <= multiplier <= 10:
        raise ValueError('RewardMultiplier must be an integer from 1 to 10')
    result = copy.deepcopy(base)
    rows = result['DT_ArenaSoloRewardTable']
    assert set(rows) == {'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Master', 'Legend'}
    for row in rows.values():
        for field in ('FirstClearReward', 'RepeatClearReward'):
            for reward in row[field]:
                for key in ('Min', 'Max'):
                    assert type(reward[key]) is int and reward[key] >= 0
                    reward[key] *= multiplier
    points = {'Arena_RankPoint_WinToNPC': 50 * multiplier}
    return result, {'BP_PalGameSetting_C': points, '/Game/Pal/Blueprint/System/BP_PalGameSetting': points.copy()}
