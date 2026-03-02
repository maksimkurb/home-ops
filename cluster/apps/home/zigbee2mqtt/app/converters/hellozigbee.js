import * as m from 'zigbee-herdsman-converters/lib/modernExtend';
import * as exposes from 'zigbee-herdsman-converters/lib/exposes';
import {Zcl} from 'zigbee-herdsman';

const e = exposes.presets;
const ea = exposes.access;

const manufacturerCode = 0x1037; // Jennic

const switchModeValues = ['toggle', 'momentary', 'multifunction'];
const switchActionValues = ['onOff', 'offOn', 'toggle'];
const relayModeValues = ['unlinked', 'front', 'single', 'double', 'tripple', 'long'];
const longPressModeValues = ['none', 'levelCtrlUp', 'levelCtrlDown'];
const operationModeValues = ['server', 'client'];
const interlockModeValues = ['none', 'mutualExclusion', 'opposite'];

const manufacturerOptions = {manufacturerCode};

function getInterlockEp(ep) {
    if (ep === 2) return 3;
    if (ep === 3) return 2;
    return null;
}

const getKey = (object, value) => {
    for (const key in object) {
        if (object[key] == value) return key;
    }
};

// Custom fromZigbee converter for genOnOffSwitchCfg cluster
const fzOnOffSwitchCfg = {
    cluster: 'genOnOffSwitchCfg',
    type: ['attributeReport', 'readResponse'],
    convert: (model, msg, publish, options, meta) => {
        const epName = getKey(model.endpoint(msg.device), msg.endpoint.ID);
        const result = {};

        if (msg.data.hasOwnProperty('65280')) {
            result[`switch_mode_${epName}`] = switchModeValues[msg.data['65280']];
        }
        if (msg.data.hasOwnProperty('switchActions')) {
            result[`switch_actions_${epName}`] = switchActionValues[msg.data['switchActions']];
        }
        if (msg.data.hasOwnProperty('65281')) {
            result[`relay_mode_${epName}`] = relayModeValues[msg.data['65281']];
        }
        if (msg.data.hasOwnProperty('65282')) {
            result[`max_pause_${epName}`] = msg.data['65282'];
        }
        if (msg.data.hasOwnProperty('65283')) {
            result[`min_long_press_${epName}`] = msg.data['65283'];
        }
        if (msg.data.hasOwnProperty('65284')) {
            result[`long_press_mode_${epName}`] = longPressModeValues[msg.data['65284']];
        }
        if (msg.data.hasOwnProperty('65285')) {
            result[`operation_mode_${epName}`] = operationModeValues[msg.data['65285']];
        }
        if (msg.data.hasOwnProperty('65286')) {
            result[`interlock_mode_${epName}`] = interlockModeValues[msg.data['65286']];
        }

        return result;
    },
};

// Custom toZigbee converter for genOnOffSwitchCfg cluster
const tzOnOffSwitchCfg = {
    key: ['switch_mode', 'switch_actions', 'relay_mode', 'max_pause', 'min_long_press', 'long_press_mode', 'operation_mode', 'interlock_mode'],
    convertGet: async (entity, key, meta) => {
        if (key === 'switch_actions') {
            await entity.read('genOnOffSwitchCfg', ['switchActions']);
        } else {
            const lookup = {
                switch_mode: 65280,
                relay_mode: 65281,
                max_pause: 65282,
                min_long_press: 65283,
                long_press_mode: 65284,
                operation_mode: 65285,
                interlock_mode: 65286,
            };
            await entity.read('genOnOffSwitchCfg', [lookup[key]], manufacturerOptions);
        }
    },
    convertSet: async (entity, key, value, meta) => {
        let payload = {};
        let newValue = value;

        switch (key) {
        case 'switch_mode':
            newValue = switchModeValues.indexOf(value);
            payload = {65280: {value: newValue, type: Zcl.DataType.ENUM8}};
            await entity.write('genOnOffSwitchCfg', payload, manufacturerOptions);
            break;
        case 'switch_actions':
            newValue = switchActionValues.indexOf(value);
            payload = {switchActions: newValue};
            await entity.write('genOnOffSwitchCfg', payload);
            break;
        case 'relay_mode':
            newValue = relayModeValues.indexOf(value);
            payload = {65281: {value: newValue, type: Zcl.DataType.ENUM8}};
            await entity.write('genOnOffSwitchCfg', payload, manufacturerOptions);
            break;
        case 'max_pause':
            payload = {65282: {value: value, type: Zcl.DataType.UINT16}};
            await entity.write('genOnOffSwitchCfg', payload, manufacturerOptions);
            break;
        case 'min_long_press':
            payload = {65283: {value: value, type: Zcl.DataType.UINT16}};
            await entity.write('genOnOffSwitchCfg', payload, manufacturerOptions);
            break;
        case 'long_press_mode':
            newValue = longPressModeValues.indexOf(value);
            payload = {65284: {value: newValue, type: Zcl.DataType.ENUM8}};
            await entity.write('genOnOffSwitchCfg', payload, manufacturerOptions);
            break;
        case 'operation_mode':
            newValue = operationModeValues.indexOf(value);
            payload = {65285: {value: newValue, type: Zcl.DataType.ENUM8}};
            await entity.write('genOnOffSwitchCfg', payload, manufacturerOptions);
            break;
        case 'interlock_mode':
            newValue = interlockModeValues.indexOf(value);
            payload = {65286: {value: newValue, type: Zcl.DataType.ENUM8}};
            entity.write('genOnOffSwitchCfg', payload, manufacturerOptions);

            const interlockEp = getInterlockEp(entity.ID);
            if (interlockEp) {
                meta.device.getEndpoint(interlockEp).read('genOnOffSwitchCfg', [65286], manufacturerOptions);
            }
            break;
        }

        return {state: {[key]: value}};
    },
};

// Custom fromZigbee converter for multistate input (button actions)
const fzMultistateInput = {
    cluster: 'genMultistateInput',
    type: ['attributeReport', 'readResponse'],
    convert: (model, msg, publish, options, meta) => {
        const actionLookup = {0: 'release', 1: 'single', 2: 'double', 3: 'tripple', 255: 'hold'};
        const value = msg.data['presentValue'];
        const action = actionLookup[value];

        const lookup = model.endpoint(msg.device);
        const epName = getKey(lookup, msg.endpoint.ID);
        return {action: `${action}_${epName}`};
    },
};

// Custom modernExtend for HelloZigbee switch settings
function helloZigbeeSwitchSettings(args = {}) {
    const {endpointNames, enableInterlock = false} = args;

    const exposesArr = [];
    for (const epName of endpointNames) {
        const swSettings = e.composite(`${epName} Button Settings`, epName, ea.ALL)
            .withDescription(`Settings for the ${epName} button`)
            .withFeature(e.enum('operation_mode', ea.ALL, operationModeValues))
            .withFeature(e.enum('switch_mode', ea.ALL, switchModeValues))
            .withFeature(e.enum('switch_actions', ea.ALL, switchActionValues))
            .withFeature(e.enum('relay_mode', ea.ALL, relayModeValues))
            .withFeature(e.enum('long_press_mode', ea.ALL, longPressModeValues));

        if (enableInterlock) {
            swSettings.withFeature(e.enum('interlock_mode', ea.ALL, interlockModeValues));
        }

        swSettings.withProperty('').withEndpoint(epName);
        exposesArr.push(swSettings);
    }

    return {
        exposes: exposesArr,
        fromZigbee: [fzOnOffSwitchCfg],
        toZigbee: [tzOnOffSwitchCfg],
        isModernExtend: true,
    };
}

// Custom modernExtend for "both buttons" endpoint settings
function helloZigbeeBothButtons(args = {}) {
    const {endpointName = 'both'} = args;

    const sw = e.composite('Both Buttons', endpointName, ea.ALL)
        .withDescription('Settings for both buttons pressed together')
        .withFeature(e.enum('switch_mode', ea.ALL, switchModeValues))
        .withFeature(e.enum('switch_actions', ea.ALL, switchActionValues))
        .withFeature(e.enum('relay_mode', ea.ALL, relayModeValues))
        .withFeature(e.enum('long_press_mode', ea.ALL, longPressModeValues))
        .withProperty('').withEndpoint(endpointName);

    return {
        exposes: [sw],
        isModernExtend: true,
    };
}

// Custom modernExtend for multistate button actions
function helloZigbeeActions(args = {}) {
    const {endpointNames} = args;
    const actions = ['single', 'double', 'triple', 'hold', 'release'];
    const actionList = endpointNames.flatMap((ep) => actions.map((a) => `${a}_${ep}`));

    return {
        exposes: [e.action(actionList)],
        fromZigbee: [fzMultistateInput],
        isModernExtend: true,
    };
}

// Custom modernExtend for initial attribute reads on configure
function helloZigbeeConfigure() {
    return {
        configure: [
            async (device, coordinatorEndpoint) => {
                for (const ep of device.endpoints) {
                    if (ep.supportsInputCluster('genOnOff')) {
                        await ep.read('genOnOff', ['onOff']);
                    }
                    if (ep.supportsOutputCluster('genOnOff')) {
                        await ep.read('genOnOffSwitchCfg', ['switchActions']);
                        await ep.read('genOnOffSwitchCfg', [65280, 65281, 65282, 65283, 65284, 65285], manufacturerOptions);
                    }
                }
            },
        ],
        isModernExtend: true,
    };
}

const definitions = [
    {
        zigbeeModel: ['hello.zigbee.E75-2G4M10S'],
        model: 'E75-2G4M10S',
        vendor: 'DIY',
        description: 'Hello Zigbee Switch based on E75-2G4M10S module',
        extend: [
            m.deviceEndpoints({endpoints: {common: 1, left: 2, right: 3, both: 4}}),
            m.deviceTemperature(),
            m.onOff({powerOnBehavior: false, endpointNames: ['left', 'right']}),
            m.commandsOnOff({endpointNames: ['left', 'right', 'both']}),
            m.commandsLevelCtrl({endpointNames: ['left', 'right', 'both']}),
            helloZigbeeActions({endpointNames: ['left', 'right', 'both']}),
            helloZigbeeSwitchSettings({endpointNames: ['left', 'right'], enableInterlock: true}),
            helloZigbeeBothButtons({endpointName: 'both'}),
            helloZigbeeConfigure(),
        ],
    },
    {
        zigbeeModel: ['hello.zigbee.QBKG11LM'],
        model: 'QBKG11LM',
        vendor: 'DIY',
        description: 'Hello Zigbee Switch firmware for Aqara QBKG11LM',
        extend: [
            m.deviceEndpoints({endpoints: {common: 1, button: 2}}),
            m.deviceTemperature(),
            m.onOff({powerOnBehavior: false, endpointNames: ['button']}),
            m.commandsOnOff({endpointNames: ['button']}),
            m.commandsLevelCtrl({endpointNames: ['button']}),
            helloZigbeeActions({endpointNames: ['button']}),
            helloZigbeeSwitchSettings({endpointNames: ['button'], enableInterlock: false}),
            helloZigbeeConfigure(),
        ],
    },
    {
        zigbeeModel: ['hello.zigbee.QBKG12LM'],
        model: 'QBKG12LM',
        vendor: 'DIY',
        description: 'Hello Zigbee Switch firmware for Aqara QBKG12LM',
        extend: [
            m.deviceEndpoints({endpoints: {common: 1, left: 2, right: 3, both: 4}}),
            m.deviceTemperature(),
            m.onOff({powerOnBehavior: false, endpointNames: ['left', 'right']}),
            m.commandsOnOff({endpointNames: ['left', 'right', 'both']}),
            m.commandsLevelCtrl({endpointNames: ['left', 'right', 'both']}),
            helloZigbeeActions({endpointNames: ['left', 'right', 'both']}),
            helloZigbeeSwitchSettings({endpointNames: ['left', 'right'], enableInterlock: true}),
            helloZigbeeBothButtons({endpointName: 'both'}),
            helloZigbeeConfigure(),
        ],
    },
];

export default definitions;
