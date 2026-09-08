"""Original rigid-part robots and weapons. Python stdlib -> editable animated GLB.

Units are metres; forward is +Z. No downloaded meshes, textures or skeletons.
Run from any directory: python tools/art/generate_sentinel_assets.py
"""
import json
import math
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "assets/models/sentinel"


class Model:
    def __init__(self):
        self.data = bytearray()
        self.doc = dict(asset={"version": "2.0", "generator": "Sentinel workshop"},
                        scene=0, scenes=[{"nodes": []}], nodes=[], meshes=[],
                        materials=[], bufferViews=[], accessors=[], animations=[])
        self.materials = {}

    def material(self, name, color, metal=0.0, rough=0.5, emission=None):
        value = {"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": [*color, 1], "metallicFactor": metal, "roughnessFactor": rough}}
        if emission:
            value["emissiveFactor"] = emission
        self.materials[name] = len(self.doc["materials"])
        self.doc["materials"].append(value)

    def accessor(self, rows, kind):
        count = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[kind]
        flat = [v for row in rows for v in (row if isinstance(row, (list, tuple)) else [row])]
        offset = len(self.data)
        self.data.extend(struct.pack("<" + "f" * len(flat), *flat))
        view = len(self.doc["bufferViews"])
        self.doc["bufferViews"].append(dict(buffer=0, byteOffset=offset, byteLength=4 * len(flat)))
        result = len(self.doc["accessors"])
        self.doc["accessors"].append(dict(bufferView=view, componentType=5126,
            count=len(rows), type=kind, min=[min(flat[i::count]) for i in range(count)],
            max=[max(flat[i::count]) for i in range(count)]))
        return result

    def node(self, name, parent=None, pos=(0, 0, 0), rotation=None):
        index = len(self.doc["nodes"])
        value = dict(name=name, translation=list(pos))
        if rotation:
            value["rotation"] = rotation
        self.doc["nodes"].append(value)
        container = self.doc["scenes"][0]["nodes"] if parent is None else self.doc["nodes"][parent].setdefault("children", [])
        container.append(index)
        return index

    def box(self, name, size, pos, material, parent, bevel=0.025, rotation=None):
        # Six faces, twelve chamfers and eight corner triangles, with flat normals.
        half = [v / 2 for v in size]
        bevel = min(bevel, min(half) * 0.4)
        inset = [v - bevel for v in half]
        faces = []
        for axis in range(3):
            others = [i for i in range(3) if i != axis]
            for sign in (-1, 1):
                face = []
                for u, v in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    p = [0, 0, 0]
                    p[axis] = sign * half[axis]
                    p[others[0]], p[others[1]] = u * inset[others[0]], v * inset[others[1]]
                    face.append(p)
                faces.append(face)
        for a, b in ((0, 1), (0, 2), (1, 2)):
            c = 3 - a - b
            for sa in (-1, 1):
                for sb in (-1, 1):
                    face = []
                    for outer, sc in ((0, -1), (1, -1), (1, 1), (0, 1)):
                        p = [0, 0, 0]
                        p[a] = sa * (half[a] if outer == 0 else inset[a])
                        p[b] = sb * (inset[b] if outer == 0 else half[b])
                        p[c] = sc * inset[c]
                        face.append(p)
                    faces.append(face)
        for x in (-1, 1):
            for y in (-1, 1):
                for z in (-1, 1):
                    signs = [x, y, z]
                    faces.append([[signs[j] * (half[j] if j == i else inset[j]) for j in range(3)] for i in range(3)])
        vertices, normals = [], []
        for face in faces:
            u = [face[1][i] - face[0][i] for i in range(3)]
            v = [face[2][i] - face[0][i] for i in range(3)]
            normal = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
            if sum(normal[i] * face[0][i] for i in range(3)) < 0:
                face.reverse()
                normal = [-v for v in normal]
            length = math.sqrt(sum(v*v for v in normal))
            normal = [v / length for v in normal]
            for i in range(1, len(face)-1):
                vertices.extend([face[0], face[i], face[i+1]])
                normals.extend([normal]*3)
        mesh = len(self.doc["meshes"])
        self.doc["meshes"].append(dict(name=name, primitives=[dict(attributes={
            "POSITION": self.accessor(vertices, "VEC3"), "NORMAL": self.accessor(normals, "VEC3")},
            material=self.materials[material])]))
        node = self.node(name, parent, pos, rotation)
        self.doc["nodes"][node]["mesh"] = mesh
        return node

    def animation(self, name, duration, tracks):
        animation = dict(name=name, samplers=[], channels=[])
        for node, path, values in tracks:
            times = [duration * i / (len(values)-1) for i in range(len(values))]
            index = len(animation["samplers"])
            animation["samplers"].append(dict(input=self.accessor(times, "SCALAR"),
                output=self.accessor(values, "VEC4" if path == "rotation" else "VEC3"), interpolation="LINEAR"))
            animation["channels"].append(dict(sampler=index, target=dict(node=node, path=path)))
        self.doc["animations"].append(animation)

    def save(self, filename):
        self.doc["buffers"] = [{"byteLength": len(self.data)}]
        if not self.doc["animations"]:
            del self.doc["animations"]
        text = json.dumps(self.doc, separators=(",", ":")).encode()
        text += b" " * (-len(text) % 4)
        self.data += b"\0" * (-len(self.data) % 4)
        (OUT / filename).write_bytes(struct.pack("<III", 0x46546c67, 2, 28 + len(text) + len(self.data))
            + struct.pack("<II", len(text), 0x4e4f534a) + text
            + struct.pack("<II", len(self.data), 0x004e4942) + self.data)


def quat(axis, angle):
    return [*(math.sin(angle / 2) if i == axis else 0 for i in range(3)), math.cos(angle / 2)]


def palette():
    model = Model()
    model.material("Ceramic", (.64, .70, .69), .25, .42)
    model.material("Frame", (.045, .07, .09), .65, .4)
    model.material("Steel", (.26, .33, .36), .8, .33)
    model.material("TeamPaint", (.06, .29, .39), .35, .4)
    model.material("Sensor", (.12, .8, .95), .1, .25, (.08, .65, .9))
    model.material("Warning", (.94, .49, .09), .2, .45)
    model.material("Rubber", (.025, .03, .04), 0, .85)
    return model


def robot():
    m = palette()
    root = m.node("RobotRig")
    torso = m.node("Torso", root, (0, 1.10, 0))
    m.box("Spine", (.24, .44, .25), (0, -.03, -.05), "Frame", torso)
    m.box("Breastplate", (.59, .39, .39), (0, .07, 0), "Ceramic", torso, .065)
    m.box("ChestInset", (.38, .16, .055), (0, .08, .208), "Frame", torso)
    m.box("ChestStripe", (.33, .055, .028), (0, .13, .242), "TeamPaint", torso, .005)
    for x in (-.09, 0, .09):
        m.box("ChestLight", (.034, .04, .026), (x, .035, .243), "Sensor", torso, .004)
    m.box("Abdomen", (.34, .17, .3), (0, -.2, 0), "Steel", torso)
    for y in (-.15, -.20, -.25):
        m.box("AbdomenRib", (.28, .025, .035), (0, y, .17), "Frame", torso, .004)
    m.box("Pack", (.4, .37, .21), (0, .06, -.28), "Frame", torso)
    for x in (-.13, .13):
        m.box("PackCell", (.09, .27, .06), (x, .06, -.41), "TeamPaint", torso, .015)
        m.box("PackLight", (.045, .025, .02), (x, .19, -.45), "Sensor", torso, .003)
    m.node("WeaponSocket", torso, (.20, -.04, .18))
    m.box("Neck", (.14, .14, .14), (0, .33, 0), "Steel", torso)
    head = m.node("Head", torso, (0, .48, 0))
    m.box("Helmet", (.37, .29, .33), (0, 0, 0), "Ceramic", head, .055)
    m.box("Face", (.29, .17, .045), (0, -.015, .166), "Frame", head)
    m.box("Visor", (.245, .045, .025), (0, .02, .196), "Sensor", head, .008)
    m.box("Jaw", (.20, .065, .04), (0, -.12, .17), "Steel", head, .015)
    m.box("Crown", (.11, .035, .23), (0, .157, -.025), "TeamPaint", head, .008)
    m.box("Antenna", (.026, .20, .025), (.20, .12, -.06), "Frame", head, .005)
    m.box("AntennaTip", (.04, .04, .04), (.20, .23, -.06), "Sensor", head, .005)
    arms, legs, knees = [], [], []
    for side in (-1, 1):
        arm = m.node("ArmL" if side < 0 else "ArmR", torso, (side*.39, .20, 0))
        arms.append(arm)
        m.box("ShoulderCore", (.19, .20, .22), (0, 0, 0), "Steel", arm)
        m.box("ShoulderArmor", (.25, .22, .32), (side*.04, .04, 0), "TeamPaint", arm, .045)
        m.box("ShoulderBand", (.20, .037, .025), (side*.04, .08, .17), "Warning", arm, .005)
        m.box("UpperArm", (.14, .23, .17), (side*.035, -.19, .04), "Frame", arm)
        elbow = m.node("Elbow", arm, (side*.035, -.29, .1))
        m.box("ElbowHub", (.19, .13, .16), (0, 0, 0), "Steel", elbow)
        end = (.20 if side > 0 else .07, 1.05, .28 if side > 0 else .62)
        start = (side*.425, 1.01, .1)
        vector = [end[i]-start[i] for i in range(3)]
        length = math.sqrt(sum(v*v for v in vector))
        direction = [v/length for v in vector]
        rotation = [direction[2], 0, -direction[0], 1+direction[1]]
        magnitude = math.sqrt(sum(v*v for v in rotation))
        rotation = [v/magnitude for v in rotation]
        m.box("Forearm", (.16, length, .18), tuple(v/2 for v in vector), "Ceramic", elbow, .026, rotation)
        m.box("Hand", (.135, .13, .15), vector, "Rubber", elbow, .022)
    m.box("Pelvis", (.42, .19, .30), (0, .79, 0), "Frame", root)
    m.box("Belt", (.43, .08, .06), (0, .82, .17), "TeamPaint", root)
    for side in (-1, 1):
        leg = m.node("LegL" if side < 0 else "LegR", root, (side*.18, .76, 0))
        legs.append(leg)
        m.box("HipJoint", (.15, .15, .19), (0, 0, 0), "Steel", leg)
        m.box("Thigh", (.205, .27, .225), (0, -.17, 0), "Ceramic", leg, .035)
        m.box("ThighPanel", (.13, .15, .035), (0, -.16, .126), "TeamPaint", leg, .01)
        knee = m.node("Knee", leg, (0, -.34, .015))
        knees.append(knee)
        m.box("KneeHub", (.21, .14, .19), (0, 0, 0), "Frame", knee)
        m.box("KneeGuard", (.18, .14, .1), (0, 0, .12), "Ceramic", knee)
        m.box("Shin", (.17, .255, .19), (0, -.18, -.005), "Ceramic", knee)
        m.box("ShinStripe", (.055, .15, .025), (0, -.17, .103), "TeamPaint", knee, .006)
        m.box("Boot", (.25, .14, .38), (0, -.35, .075), "Frame", knee, .03)
        m.box("ToeArmor", (.235, .055, .18), (0, -.30, .15), "Steel", knee, .018)
        m.box("Sole", (.25, .035, .35), (0, -.415, .075), "Rubber", knee, .008)
    m.animation("idle", 2.4, [(torso, "translation", [(0,1.10,0),(0,1.115,0),(0,1.10,0)]),
                             (head, "rotation", [quat(1,-.04),quat(1,.04),quat(1,-.04)])])
    tracks = [(torso,"translation",[(0,1.10,0),(0,1.12,0),(0,1.10,0),(0,1.12,0),(0,1.10,0)])]
    for i, leg in enumerate(legs):
        sign = 1 if i == 0 else -1
        tracks.append((leg,"rotation",[quat(0,v*sign) for v in (-.42,0,.42,0,-.42)]))
        tracks.append((knees[i],"rotation",[quat(0,v) for v in ((0,.55,0,.08,0) if i == 0 else (0,.08,0,.55,0))]))
    m.animation("walk", .65, tracks)
    m.animation("shoot", .24, [(torso,"translation",[(0,1.10,0),(0,1.10,-.04),(0,1.10,0)]),
                              (head,"rotation",[quat(0,0),quat(0,-.07),quat(0,0)])])
    m.animation("hit", .34, [(torso,"rotation",[quat(0,0),quat(0,-.22),quat(0,0)]),
                            (head,"rotation",[quat(2,0),quat(2,.18),quat(2,0)])])
    tracks = [(root,"rotation",[quat(0,0),quat(0,-.35),quat(0,-1.5)]),
              (root,"translation",[(0,0,0),(0,-.05,-.12),(0,.20,-.32)]),
              (head,"rotation",[quat(2,0),quat(2,.2),quat(2,.35)])]
    tracks.extend((leg,"rotation",[quat(0,0),quat(0,-.3),quat(0,-.25)]) for leg in legs)
    tracks.extend((knee,"rotation",[quat(0,0),quat(0,.55),quat(0,.45)]) for knee in knees)
    tracks.extend((arm,"rotation",[quat(2,0),quat(2,.2*s),quat(2,.55*s)]) for arm,s in zip(arms,(1,-1)))
    m.animation("death", .7, tracks)
    m.save("sentinel_robot.glb")


def weapon(kind):
    m = palette()
    root = m.node(kind)
    short = kind == "breach_shotgun"
    def box(name, size, pos, mat="Frame", bevel=.015):
        m.box(name, size, pos, mat, root, bevel)
    box("Receiver", (.18 if short else .14,.16,.43), (0,.03,.24), bevel=.028)
    box("SidePanel", (.193 if short else .15,.085,.23), (0,.04,.22), "Ceramic")
    box("Grip", (.09,.18,.09), (0,-.115,.12), "Rubber")
    box("Stock", (.13,.17,.22), (0,.015,-.075), bevel=.025)
    box("ButtPad", (.16,.19,.055), (0,.015,-.21), "Rubber")
    box("Rail", (.065,.035,.31), (0,.13,.27), "Steel", .006)
    box("SightBase", (.09,.065,.11), (0,.18,.16), bevel=.009)
    box("SightLens", (.05,.034,.012), (0,.18,.222), "Sensor", .004)
    if short:
        for x in (-.047,.047):
            box("Barrel", (.075,.075,.29), (x,.03,.57), "Steel", .012)
            box("MuzzleBore", (.05,.05,.012), (x,.03,.721), "Rubber", .008)
        box("Pump", (.21,.10,.20), (0,-.048,.51), "TeamPaint")
        for z in (.45,.50,.55):
            box("PumpRib", (.22,.025,.025), (0,-.045,z), bevel=.004)
        for z in (.15,.23,.31):
            box("Shell", (.032,.10,.04), (.112,.025,z), "Warning", .009)
        muzzle = (0,.03,.73)
    else:
        box("Handguard", (.15,.14,.27), (0,.02,.54), "TeamPaint", .021)
        for z in (.46,.53,.60):
            box("Vent", (.16,.045,.036), (0,.035,z), bevel=.005)
        length = .46 if kind == "marksman_rifle" else .25
        box("Barrel", (.067,.067,length), (0,.02,.645+length/2), "Steel", .01)
        tip = .66+length
        box("MuzzleBrake", (.11,.1,.11), (0,.02,tip), bevel=.016)
        box("Bore", (.05,.046,.008), (0,.02,tip+.06), "Rubber", .007)
        box("Magazine", (.09,.22,.12), (0,-.15,.30), bevel=.017)
        box("MagazineStripe", (.096,.038,.124), (0,-.14,.30), "Warning", .006)
        if kind == "marksman_rifle":
            box("Scope", (.11,.10,.30), (0,.23,.18), "Frame")
            box("ScopeLens", (.075,.066,.015), (0,.23,.339), "Sensor", .009)
        muzzle = (0,.02,tip+.07)
    m.node("Muzzle", root, muzzle)
    m.save(kind+".glb")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    robot()
    for variant in ("lancer_rifle", "breach_shotgun", "marksman_rifle"):
        weapon(variant)
    print("Generated robot with five animation clips and three weapon variants.")
