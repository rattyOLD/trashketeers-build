class_name Premium
extends RefCounted
## VIP-статус (5 уровней, 30 дней, доплата поднимает уровень) и разовая покупка «Без рекламы».
## Все бонусы - ускорение прогресса и удобство, боевых характеристик VIP не даёт.

## Пока платёжного шлюза нет, покупки выдаются бесплатно (тестовая сборка).
const PAYMENTS_LIVE := false
const VIP_DAYS := 30
const NO_ADS_PRICE := 2.99
const VIP_LEVELS := [
	{"level": 1, "price": 2.99, "color": Color("#7fd0ff"), "perks": ["Ежедневный подарок x2", "+1 попытка рекламы за монеты и неонит", "Значок VIP в шапке", "Подарки во вкладках чаще: -20 минут за каждый уровень VIP"]},
	{"level": 2, "price": 5.99, "color": Color("#7ed321"), "perks": ["Без рекламы после боссов", "+10% монет за забег"]},
	{"level": 3, "price": 9.99, "color": Color("#b36bff"), "perks": ["Бесплатный сундук каждые 3 часа вместо 4", "+1 бесплатный реролл за забег"]},
	{"level": 4, "price": 14.99, "color": Color("#ff9a3d"), "perks": ["+15% монет за забег (вместо +10%)", "+15% опыта аккаунта", "+10% очков Боевого пропуска", "Шанс неонита в подарках x1.5"]},
	{"level": 5, "price": 24.99, "color": Color("#ffd257"), "perks": ["Бесплатный сундук выдаёт редкий", "Ежедневный подарок x3", "+20% монет за забег (вместо +15%)", "До 3 неонита из подарков в день вместо 2"]},
]
const COIN_BONUS := [0.0, 0.0, 0.10, 0.10, 0.15, 0.20]
const XP_BONUS := [0.0, 0.0, 0.0, 0.0, 0.15, 0.15]


static func level() -> int:
	if int(SaveService.data["vip_until"]) <= int(Time.get_unix_time_from_system()):
		return 0
	return clampi(int(SaveService.data["vip_level"]), 0, VIP_LEVELS.size())


static func days_left() -> int:
	var left := int(SaveService.data["vip_until"]) - int(Time.get_unix_time_from_system())
	return maxi(int(ceil(left / 86400.0)), 0)


static func price_text(price: float) -> String:
	return "$%.2f" % price


static func level_price(target: int) -> float:
	return float(VIP_LEVELS[target - 1]["price"])


## Сколько платить за уровень target: с нуля - полная цена, выше текущего - доплата, тот же или ниже - продление.
static func cost_for(target: int) -> float:
	var current := level()
	if current > 0 and target > current:
		return level_price(target) - level_price(current)
	return level_price(target)


static func buy_vip(target: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	var until := int(SaveService.data["vip_until"])
	if level() < target:
		SaveService.data["vip_level"] = target
	if until <= now or target <= level():
		SaveService.data["vip_until"] = maxi(until, now) + VIP_DAYS * 86400
	SaveService.save_data()


static func buy_no_ads() -> void:
	SaveService.data["no_ads"] = true
	SaveService.save_data()


static func ads_removed() -> bool:
	return bool(SaveService.data["no_ads"]) or level() >= 2


static func coin_bonus() -> float:
	return float(COIN_BONUS[level()])


static func xp_bonus() -> float:
	return float(XP_BONUS[level()])


static func pass_bonus() -> float:
	return 0.10 if level() >= 4 else 0.0


static func daily_mult() -> int:
	var current := level()
	if current >= 5:
		return 3
	return 2 if current >= 1 else 1


static func ad_bonus() -> int:
	return 1 if level() >= 1 else 0


static func chest_cooldown() -> int:
	return (3 if level() >= 3 else 4) * 3600


static func chest_tier() -> String:
	return "rare" if level() >= 5 else "common"


static func reroll_bonus() -> int:
	return 1 if level() >= 3 else 0
