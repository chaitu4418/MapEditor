const DisableBlueprintCommand = function (gameObjectTransferData) {

    Command.call(this);

    this.type = 'DisableBlueprintCommand';
    this.name = 'Disable Blueprint';
    this.gameObjectTransferData = gameObjectTransferData;
};


DisableBlueprintCommand.prototype = {
    execute: function () {
        let gameObjectTransferData = {
            'guid': this.gameObjectTransferData.guid
        };
        editor.vext.SendCommand(new VextCommand(this.type, gameObjectTransferData))
    },

    undo: function () {
        editor.vext.SendCommand(new VextCommand("EnableBlueprintCommand", this.gameObjectTransferData))
    },
};

