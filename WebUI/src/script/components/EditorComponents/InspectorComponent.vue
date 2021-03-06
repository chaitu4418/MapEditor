import {INode} from "infinite-tree";
<template>
	<EditorComponent class="inspector-component" title="Inspector">
		<div v-if="!isEmpty">
			<div class="header">
				<div class="title">Entity</div>
				<div class="enable-container">
					<label class="enable-label" for="enabled">Enabled:</label>
					<input class="enable-input" type="checkbox" id="enabled" :disabled="multiSelection" ref="enableInput" v-model="enabled" @change="onEnableChange">
				</div>
				<div class="transform-container">
					<label class="name-label" for="name">GUID:</label><input class="guid-input" :value="gameObjectGuid" :disabled="true">
					<label class="name-label" for="name">Name:</label><input class="name-input" :value="displayName" :disabled="multiSelection" @input="onNameChange" id="name">
					<linear-transform-control class="lt-control" :hideLabel="false"
											:position="position" :rotation="rotation" :scale="scale"
											@input="onInput" @startDrag="onStartDrag" @endDrag="onEndDrag" @quatUpdated="quatUpdated"/>
				</div>
				<div class="blueprint-container" v-if="!multiSelection && !isEmpty">
					<div class="title">Blueprint</div>
					<label class="name-label" for="bp-name">Name:</label>
					<input class="name-input" id="bp-name" disabled="true" :value="blueprintName">

					<label class="name-label" for="bp-type">Type:</label>
					<input class="name-input" id="bp-type" disabled="true" :value="blueprintType">

					<label class="name-label" for="bp-instance-guid">Instance GUID:</label>
					<input class="name-input" id="bp-instance-guid" disabled="true" :value="blueprintGuid">

					<label class="name-label" for="bp-partition-guid">Partition GUID:</label>
					<input class="name-input" id="bp-partition-guid" disabled="true" :value="blueprintPartitionGuid">
				</div>
			</div>
		</div>
	</EditorComponent>
</template>

<script lang="ts">
import { Component, Ref } from 'vue-property-decorator';
import EditorComponent from './EditorComponent.vue';
import 'vue-virtual-scroller/dist/vue-virtual-scroller.css';
import { signals } from '@/script/modules/Signals';
import SetObjectNameCommand from '@/script/commands/SetObjectNameCommand';
import LinearTransformControl from '@/script/components/controls/LinearTransformControl.vue';
import { SelectionGroup } from '@/script/types/SelectionGroup';
import { IVec3, Vec3 } from '@/script/types/primitives/Vec3';
import { IQuat, Quat } from '@/script/types/primitives/Quat';
import { GameObject } from '@/script/types/GameObject';

@Component({ components: { LinearTransformControl, EditorComponent } })
export default class InspectorComponent extends EditorComponent {
	private group: SelectionGroup | null = null;
	private position: IVec3 = new Vec3().toTable();
	private scale: IVec3 = new Vec3(1, 1, 1).toTable();
	private rotation: IQuat = new Quat().toTable();
	private dragging = false;
	private enabled = true;
	private blueprintName: string = '';
	private blueprintType: string = '';
	private blueprintGuid: string = '';
	private blueprintPartitionGuid: string = '';

	@Ref('enableInput')
	enableInput!: HTMLInputElement;

	constructor() {
		super();
		signals.selectionGroupChanged.connect(this.onSelectionGroupChanged.bind(this));
		signals.selectedGameObject.connect(this.onSelection.bind(this));
		signals.deselectedGameObject.connect(this.onSelection.bind(this));
		signals.objectChanged.connect(this.onObjectChanged.bind(this));
	}

	private onObjectChanged(gameObject: GameObject, field: string, value: any) {
		if (!gameObject || !this.group) {
			return;
		}
		if (field === 'enabled' && this.group.isSelected(gameObject) && this.group.selectedGameObjects.length === 1) {
			this.enabled = value;
		}
	}

	private onInput() {
		if (this.group !== null) {
			// Move selection group to the new position.
			this.group.position.set(this.position.x, this.position.y, this.position.z);
			this.group.scale.set(this.scale.x, this.scale.y, this.scale.z);
			this.group.rotation.setFromQuaternion(Quat.setFromTable(this.rotation));

			this.group.updateMatrix();
			// Update inspector transform.
			window.editor.threeManager.nextFrame(() => {
				if (this.group) {
					this.group.onClientOnlyMove();
				}
				window.editor.threeManager.setPendingRender();
			});
			window.editor.threeManager.setPendingRender();
		}
	}

	private onSelection() {
		this.$nextTick(() => {
			if (this.multiSelection || this.isEmpty || !this.group) {
				return;
			}
			const selectedGameObject = this.group.selectedGameObjects[0];
			if (!selectedGameObject) return;
			this.blueprintGuid = selectedGameObject.blueprintCtrRef.instanceGuid.toString();
			this.blueprintName = selectedGameObject.blueprintCtrRef.name.toString();
			this.blueprintType = selectedGameObject.blueprintCtrRef.typeName.toString();
			this.blueprintPartitionGuid = selectedGameObject.blueprintCtrRef.partitionGuid.toString();
		});
	}

	get isEmpty() {
		if (this.group) {
			return (this.group.selectedGameObjects.length === 0);
		}
		return true;
	}

	get multiSelection() {
		if (this.group) {
			return (this.group.selectedGameObjects.length > 1);
		}
		return false;
	}

	get displayName() {
		if (!this.group || this.isEmpty) {
			return '';
		}
		if (this.multiSelection) {
			return 'Multiselection';
		} else {
			return this.group.selectedGameObjects[0].name;
		}
	}

	get gameObjectGuid() {
		if (!this.group || this.isEmpty) {
			return '';
		}
		if (this.multiSelection) {
			return 'Multiselection';
		} else {
			return this.group.selectedGameObjects[0].guid.toString();
		}
	}

	onStartDrag() {
		// console.log('Drag start');
		this.dragging = true;
	}

	onEndDrag() {
		// console.log('Drag end');
		if (this.group) {
			this.group.onClientOnlyMoveEnd();
			this.dragging = false;
		}
	}

	private quatUpdated(newQuat: IQuat) {
		this.rotation = newQuat;
	}

	private onSelectionGroupChanged(group: SelectionGroup) {
		this.$nextTick(() => {
			if (!this.group) {
				this.group = group;
			}
			if (!this.dragging) {
				// Update inspector transform.
				this.position = this.group.transform.trans.toTable();
				this.scale = this.group.transform.scale.toTable();
				this.rotation = this.group.transform.rotation.toTable();
			}
			this.enabled = this.group.selectedGameObjects[0].enabled;
		});
	}

	private onEnableChange(e: Event) {	// TODO Fool: Enabling and disabling should work for multi-selection too.
		this.$nextTick(() => {
			if (!this.group) {
				return;
			}

			if (this.enabled) {
				this.group.enable();
			} else {
				this.group.disable();
			}
		});
	}

	private onNameChange(e: InputEvent) {
		if (!this.group || this.isEmpty) {
			return;
		}
		if ((e.target as any).value) {
			window.editor.execute(new SetObjectNameCommand(this.group.selectedGameObjects[0].getGameObjectTransferData(), (e.target as any).value));
		}
	}
}
</script>
<style lang="scss" scoped>
	.transformControls::v-deep input {
		width: 100%;
	}
	.inspector-component {
		.title {
			margin: 1vmin 0;
			font-size: 1.5em;
			font-weight: bold;
		}
		.enable-container {
			display: flex;
			flex-direction: row;
			align-content: center;
			.enable-label {
				margin: 1vmin 0;
				font-weight: bold;
			}

			.enable-input {
				height: 1.5vmin;
				margin: 1vmin 0;
			}
		}

		.name-label {
			margin: 1vmin 0;
			font-weight: bold;
		}

		.name-input {
			margin: 1vmin 0;
			border-radius: 0.1vmin;
		}
	}
</style>
