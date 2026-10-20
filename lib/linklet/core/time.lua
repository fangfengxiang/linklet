-- Strict RFC3339 UTC/offset conversion, independent of process timezone.
local _M = {}
function _M.parse(value)
    if type(value)~="string" then return nil end
    local y,m,d,h,n,s,zone = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt](%d%d):(%d%d):(%d%d)(.*)$")
    if not y then return nil end
    y,m,d,h,n,s=tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(n),tonumber(s)
    local fraction, suffix = zone:match("^(%.%d+)(.*)$")
    if fraction then zone=suffix end
    local offset=0
    if zone~="Z" and zone~="z" then
        local sign,zh,zm=zone:match("^([+-])(%d%d):(%d%d)$")
        if not sign or tonumber(zh)>23 or tonumber(zm)>59 then return nil end
        offset=(tonumber(zh)*60+tonumber(zm))*60*(sign=="+" and 1 or -1)
    end
    local leap=y%4==0 and (y%100~=0 or y%400==0)
    local days={31,leap and 29 or 28,31,30,31,30,31,31,30,31,30,31}
    if y<1 or m<1 or m>12 or d<1 or d>days[m] or h>23 or n>59 or s>59 then return nil end
    local before=y-1
    local total=365*before+math.floor(before/4)-math.floor(before/100)+math.floor(before/400)
    for i=1,m-1 do total=total+days[i] end
    return (total+d-1-719162)*86400+h*3600+n*60+s-offset+(tonumber(fraction) or 0)
end
return _M
