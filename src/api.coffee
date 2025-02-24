import { pngToSvg } from "./image"
import { request, json, buffer, respond, error, badRequest, notFound } from "./http"
import { usernameToUuid, uuidToProfile, uuidToUsernameHistory, uuidIsSlim, textureAlex, textureSteve, uuidSteve } from "./mojang"

# Get the Uuid of a user given their name.
#
# @param {string} name - Minecraft username, must be alphanumeric 16 characters.
# @returns {promise<response>} - An error or a Uuid response as text.
export uuid = (name) ->
  unless name.asUsername()
    return badRequest("Invalid format for the name '#{name}'")
  unless id = await NAMES.get(name.toLowerCase(), "text")
    unless response = await usernameToUuid(name)
      return notFound("No user with the name '#{name}' was found")
    id = response.id?.asUuid(dashed: true)
    await NAMES.put(name.toLowerCase(), id, {expirationTtl: 60 * 5})
  respond(id, text: true)

# Get the profile of a user given their Uuid or name.
#
# @param {string} id - Uuid or Minecraft username.
# @returns {promise<response>} - An error or a profile response as Json.
export user = (id) ->
  if id.asUsername()
    if (response = await uuid(id)).ok
      response = user(await response.text())
    return response
  unless id.asUuid()
    return badRequest("Invalid format for the UUID '#{id}'")
  if response = await USERS.get(id.asUuid(dashed: true), "json")
    return respond(response, json: true)
  [profile, history] = await Promise.all([
    uuidToProfile(id = id.asUuid()),
    uuidToUsernameHistory(id)])
  unless profile
    return notFound("No user with the UUID '#{id}' was found")
  unless history
    history = [name: profile.name]
  texturesRaw = profile.properties?.filter((item) -> item.name == "textures")[0] || {}
  textures = JSON.parse(atob(texturesRaw?.value || btoa("{}"))).textures || {}
  unless textures.isEmpty()
    [skin, cape] = await Promise.all([
      buffer(skinUrl) if skinUrl = textures.SKIN?.url,
      buffer(capeUrl) if capeUrl = textures.CAPE?.url])
  unless skin
    [type, skin] = if uuidIsSlim(id) then ["alex", textureAlex] else ["steve", textureSteve]
    skinUrl = "http://assets.mojang.com/SkinTemplates/#{type}.png"
  if profile.legacy || profile.demo
    date = await created(id, profile.name)
  else
    date = await created(id, profile.name)
  response =
    uuid: id = profile.id.asUuid(dashed: true)
    username: profile.name
    username_history: history.map((item) ->
      username: item.name
      changed_at: item.changedToAt?.asDate())
    textures:
      custom: !type?
      slim: textures.SKIN?.metadata?.model == "slim" || type == "alex"
      skin: {url: skinUrl, data: skin}
      cape: {url: capeUrl, data: cape} if capeUrl,
      raw: {value: texturesRaw.value, signature: texturesRaw.signature} unless texturesRaw.isEmpty()
    legacy: true if profile.legacy
    demo: true if profile.demo
    created_at: date
  await USERS.put(id, JSON.stringify(response), {expirationTtl: 60 * 5})
  respond(response, json: true)

# Approximate the date a user was created to within a day.
#
# @param {string} id - Uuid of the user.
# @param {string} name - Minecraft name of the user.
# @param {integer} lower - Lower bound of search in unix milliseconds.
# @param {integer} upper - Upper bound of search in unix milliseconds.
# @param {integer} side - Determines a left or right binary search.
# @param {boolean} accurate - Whether the results can be considered accurate.
# @returns {date} Approximate date of user creation or null if not accurate.
export created = (id, name, lower = 1230811200000, upper = Math.floor(Date.now()), side = 0, accurate = false) -> # original: 1242518400000, new fixed one: 1230811200000
  unless date = await BIRTHDAYS.get(id, "text")
    middle = lower + Math.floor((upper - lower) / 2)
    if lower.asDay() == upper.asDay()
      await BIRTHDAYS.put(id, date = if accurate then middle.asDay() else "null")
    else if response = await usernameToUuid(name, Math.floor(middle / 1000))
      return created(id, name, lower, middle, -1, accurate || side - 1 == 0)
    else
      return created(id, name, middle, upper, +1, accurate || side + 1 == 0)
  return if date == "null" then null else date

# Redirect to the avatar service to render the face of a user.
#
# @param {string} id - Uuid of the user.
# @returns {promise<response>} - Avatar response as a Svg.
export avatar = (id) ->
  if !id.asUsername() && !id.asUuid()
    return avatar(uuidSteve)
  unless svg = await AVATARS.get(id.toLowerCase(), "text")
    try
      profile = await json(user(id))
      svg = pngToSvg(profile.textures.skin.data,
        snap: true,
        view: {width: 8, height: 8},
        regions: [
          {x: 8,  y: 8, width: 8, height: 8},
          {x: 40, y: 8, width: 8, height: 8}])
      if id != uuidSteve
        options = {expirationTtl: 60 * 60}
      await AVATARS.put(id.toLowerCase(), svg, options)
    catch err
      if id == uuidSteve
        return error(err)
      else
        return avatar(uuidSteve)
  respond(svg, svg: true)
